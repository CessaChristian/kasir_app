import 'dart:math';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/app_database.dart';
import '../../../utils/crypto_utils.dart';
import '../../../utils/security/hash_utils.dart';
import '../recovery/models/recovery_result.dart';
import '../models/auth_session.dart';

/// Repository for authentication operations
class AuthRepository {
  final AppDatabase _db;

  AuthRepository(this._db);

  /// Check if an owner account exists
  Future<bool> hasOwner() async {
    final count = await (_db.select(_db.users)
          ..where((u) => u.role.equals('owner'))
          ..limit(1))
        .get();
    return count.isNotEmpty;
  }

  /// Bootstrap the owner account (first-time setup)
  /// 
  /// Can only be called once - when no owner exists
  /// Returns the created owner User
  Future<User> bootstrapOwner({
    required String username,
    required String pin,
  }) async {
    // 1. Validate that no owner exists
    if (await hasOwner()) {
      throw StateError('Owner account already exists');
    }

    // 2. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN must be 4-6 digits');
    }

    // 3. Generate salt and hash PIN
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(pin, salt);

    // 4. Generate unique ID
    final userId = _generateUserId();

    // 5. Create owner account
    final ownerCompanion = UsersCompanion.insert(
      id: Value(userId),
      username: username,
      pinHash: pinHash,
      salt: salt,
      role: 'owner',
      isActive: const Value(true),
    );

    // Jika insert throw → data TIDAK masuk DB, error valid
    await _db.into(_db.users).insert(ownerCompanion);

    // Jika getSingleOrNull null → insert BERHASIL tapi gagal baca kembali (sangat jarang)
    // Data sudah ada di DB — user bisa langsung login
    final created = await (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (created == null) {
      throw StateError('Akun berhasil dibuat. Silakan login dengan username dan PIN yang baru dibuat.');
    }
    return created;
  }

  /// Login with username and PIN
  /// 
  /// Returns AuthSession if successful, null if credentials invalid
  Future<AuthSession?> login({
    required String username,
    required String pin,
  }) async {
    // 1. Find user by username — getSingleOrNull lebih efisien dari .get().first
    final user = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username))
          ..limit(1))
        .getSingleOrNull();

    if (user == null) return null;

    // 2. Check if user is active
    if (!user.isActive) {
      throw StateError('User account is deactivated');
    }

    // 2b. S5: Cek apakah akun sedang ter-lock karena terlalu banyak gagal login.
    if (user.loginLockedUntil != null &&
        user.loginLockedUntil!.isAfter(DateTime.now())) {
      final remaining = user.loginLockedUntil!.difference(DateTime.now());
      throw StateError(
          'Akun terkunci. Coba lagi dalam ${_formatLockDuration(remaining)}.');
    }

    // 3. Verify PIN
    final isValid = CryptoUtils.verifyPin(pin, user.salt, user.pinHash);
    if (!isValid) {
      // S5: Increment login attempts + lockout dengan exponential backoff.
      await _incrementLoginAttempts(user.id);
      return null;
    }

    // S5: PIN benar → reset login attempts + clear lock.
    if (user.loginAttempts > 0 || user.loginLockedUntil != null) {
      await (_db.update(_db.users)..where((u) => u.id.equals(user.id)))
          .write(const UsersCompanion(
        loginAttempts: Value(0),
        loginLockedUntil: Value(null),
      ));
    }

    // 3b. Migrasi transparan: kalau hash masih format lama (SHA-256),
    // re-hash dengan PBKDF2 dan update DB.
    if (CryptoUtils.needsRehash(user.pinHash)) {
      final newHash = CryptoUtils.hashPin(pin, user.salt);
      await (_db.update(_db.users)..where((u) => u.id.equals(user.id)))
          .write(UsersCompanion(pinHash: Value(newHash)));
    }

    // 4. Start a new shift — I4: bungkus dengan pesan error spesifik
    // agar user tahu PIN sudah benar tapi gagal di langkah shift.
    //
    // businessId: login terjadi sebelum BusinessContext.loadInitial, jadi
    // kita query langsung dari userBusinessRoles.
    final businessId = await _getFirstBusinessId(user.id);

    final String shiftId;
    try {
      shiftId = await _startShift(user.id, businessId: businessId);
    } catch (e) {
      throw StateError(
          'PIN benar, tapi gagal membuka shift. Cek storage device dan coba lagi.');
    }

    // 5. Get user permissions
    final permissions = await _getUserPermissions(user.id, user.role);

    // 6. Create and return session (default expire: 12 jam)
    return AuthSession.create(
      userId: user.id,
      username: user.username,
      role: user.role,
      shiftId: shiftId,
      permissions: permissions,
    );
  }

  /// Logout - end the current shift
  Future<void> logout({
    required String userId,
    required String shiftId,
  }) async {
    // End the shift by setting end_at
    await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
      ShiftsCompanion(
        endAt: Value(DateTime.now()),
      ),
    );
  }

  Future<User?> getUserById(String userId) {
    return (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
  }

  /// Ambil businessId untuk _startShift saat login (sebelum
  /// BusinessContext.loadInitial dipanggil).
  /// Prioritas: business aktif terakhir yang dipersist — supaya shift login
  /// dibuka di business yang sama dengan tampilan app setelah login.
  Future<String> _getFirstBusinessId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final persistedId = prefs.getString('active_business_id');
    if (persistedId != null) {
      final persisted = await (_db.select(_db.userBusinessRoles)
            ..where((r) =>
                r.userId.equals(userId) &
                r.businessId.equals(persistedId) &
                r.deletedAt.isNull())
            ..limit(1))
          .get();
      if (persisted.isNotEmpty) return persistedId;
    }

    final roles = await (_db.select(_db.userBusinessRoles)
          ..where((r) =>
              r.userId.equals(userId) & r.deletedAt.isNull())
          ..limit(1))
        .get();
    if (roles.isNotEmpty) return roles.first.businessId;

    // Fallback: kalau user belum punya role (misal owner baru),
    // ambil business pertama dari tabel businesses.
    final businesses = await (_db.select(_db.businesses)
          ..where((b) => b.deletedAt.isNull())
          ..limit(1))
        .get();
    if (businesses.isNotEmpty) return businesses.first.id;

    // Edge case: tidak ada business sama sekali (fresh install sebelum onboarding).
    // Return string kosong — shift akan gagal FK constraint, yang memang benar
    // karena onboarding belum selesai.
    return '';
  }

  /// Start a new shift for a user di active business, atau gunakan shift aktif yang sudah ada.
  Future<String> _startShift(String userId, {required String businessId}) async {
    final existing = await (_db.select(_db.shifts)
          ..where((s) => s.userId.equals(userId))
          // Shift bersifat per business — jangan reuse shift business lain.
          ..where((s) => s.businessId.equals(businessId))
          ..where((s) => s.endAt.isNull())
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) return existing.id;

    final shiftId = _generateShiftId();
    await _db.into(_db.shifts).insert(
          ShiftsCompanion.insert(
            id: Value(shiftId),
            businessId: businessId,
            userId: userId,
          ),
        );
    return shiftId;
  }

  /// Get user permissions
  /// 
  /// For owners, returns all permission codes (always full access)
  /// For cashiers, returns only enabled permissions
  Future<List<String>> _getUserPermissions(String userId, String role) async {
    // Owner has all permissions
    if (role == 'owner') {
      final allPermissions = await _db.select(_db.permissions).get();
      return allPermissions.map((p) => p.code).toList();
    }

    // Cashier: get enabled permissions only
    final userPerms = await (_db.select(_db.userPermissions)
          ..where((up) => up.userId.equals(userId))
          ..where((up) => up.enabled.equals(true)))
        .get();

    return userPerms.map((up) => up.permissionCode).toList();
  }

  /// Get all active usernames untuk dropdown login.
  /// Aman karena dilindungi rate limit (S5) dan session anti-tamper (S6).
  Future<List<String>> getAllActiveUsernames() async {
    final users = await (_db.select(_db.users)
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.username)]))
        .get();
    return users.map((u) => u.username).toList();
  }

  // S10: Random.secure() suffix mencegah ID prediksi/collision.
  static final _secureRandom = Random.secure();

  String _generateUserId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _secureRandom.nextInt(99999).toString().padLeft(5, '0');
    return 'user_${ts}_$r';
  }

  String _generateShiftId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _secureRandom.nextInt(99999).toString().padLeft(5, '0');
    return 'shift_${ts}_$r';
  }

  // ============================================================================
  // RECOVERY CODE METHODS
  // ============================================================================

  /// Generate recovery code for owner and store hash+salt
  /// 
  /// Returns the plain recovery code (SHOW ONLY ONCE!)
  Future<String> generateAndStoreRecoveryCodeForOwner(String userId) async {
    final owner = await getUserById(userId);
    if (owner == null || owner.role != 'owner') {
      throw StateError('User is not an owner');
    }

    // Generate recovery code (formatted with dashes)
    final recoveryCode = _generateRecoveryCode();
    
    // Normalize for hashing (remove dashes)
    final normalizedCode = _normalizeRecoveryCode(recoveryCode);

    // Generate salt and hash
    final salt = _generateRecoverySalt();
    final hash = _hashRecoveryCode(normalizedCode, salt);

    // Update owner with recovery data
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        recoveryHash: Value(hash),
        recoverySalt: Value(salt),
        recoveryCreatedAt: Value(DateTime.now()),
        recoveryUsedAt: const Value(null),
        recoveryAttempts: const Value(0),
        recoveryLockedUntil: const Value(null),
      ),
    );

    return recoveryCode;
  }

  /// Check if owner recovery is currently locked
  Future<RecoveryLockStatus> getOwnerRecoveryLockStatus() async {
    final owner = await _getOwner();
    if (owner == null) {
      return RecoveryLockStatus.notLocked();
    }

    final lockUntil = owner.recoveryLockedUntil;
    if (lockUntil == null) {
      return RecoveryLockStatus.notLocked();
    }

    final now = DateTime.now();
    if (now.isBefore(lockUntil)) {
      final remaining = lockUntil.difference(now).inSeconds;
      return RecoveryLockStatus.locked(remaining);
    }

    // Lock expired, reset
    await _resetRecoveryLock(owner.id);
    return RecoveryLockStatus.notLocked();
  }

  /// Verify owner recovery code
  /// 
  /// Returns RecoveryResult with status
  /// Handles attempts tracking and locking
  Future<RecoveryResult> verifyOwnerRecoveryCode(String code) async {
    final owner = await _getOwner();
    if (owner == null) {
      return RecoveryResult.ownerNotFound();
    }

    // Check if locked
    final lockStatus = await getOwnerRecoveryLockStatus();
    if (lockStatus.isLocked) {
      return RecoveryResult.locked(seconds: lockStatus.secondsRemaining);
    }

    // Check if recovery code is set
    if (owner.recoveryHash == null || owner.recoverySalt == null) {
      return RecoveryResult.invalidCode(
        message: 'No recovery code set up for this account',
      );
    }

    // Normalize and verify
    final normalized = _normalizeRecoveryCode(code);
    final isValid = _verifyRecoveryCode(
      normalized,
      owner.recoverySalt!,
      owner.recoveryHash!,
    );

    if (!isValid) {
      await _incrementRecoveryAttempts(owner.id);
      return RecoveryResult.invalidCode();
    }

    // Migrasi transparan: kalau recovery hash masih format lama (SHA-256),
    // re-hash dengan PBKDF2 dan update DB.
    if (HashUtils.needsRehash(owner.recoveryHash!)) {
      final newHash = _hashRecoveryCode(normalized, owner.recoverySalt!);
      await (_db.update(_db.users)..where((u) => u.id.equals(owner.id)))
          .write(UsersCompanion(recoveryHash: Value(newHash)));
    }

    // Valid - reset attempts
    await _resetRecoveryAttempts(owner.id);
    return RecoveryResult.success();
  }

  /// Reset owner PIN using valid recovery code
  ///
  /// Auto-generates new recovery code after successful reset.
  ///
  /// M-B: SELURUH flow (lock check, verify recovery, update PIN, reset
  /// attempts) dijalankan dalam satu transaksi DB. Tanpa ini, ada window
  /// dimana recovery code sudah ditandai "used" (recoveryUsedAt + attempts
  /// reset) tapi update PIN gagal — owner terkunci permanen karena recovery
  /// dianggap terpakai padahal PIN tidak berubah.
  Future<RecoveryResult> resetOwnerPinWithRecoveryCode({
    required String recoveryCode,
    required String newPin,
  }) async {
    // Validasi format PIN dilakukan di luar transaksi — kalau format salah,
    // jangan sentuh DB sama sekali (tidak boleh menghitung sebagai attempt).
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      return RecoveryResult.invalidCode(
        message: 'New PIN must be 4-6 digits',
      );
    }

    return await _db.transaction<RecoveryResult>(() async {
      final owner = await _getOwner();
      if (owner == null) {
        return RecoveryResult.ownerNotFound();
      }

      // Lock check di dalam transaksi
      final lockUntil = owner.recoveryLockedUntil;
      if (lockUntil != null && DateTime.now().isBefore(lockUntil)) {
        final remaining = lockUntil.difference(DateTime.now()).inSeconds;
        return RecoveryResult.locked(seconds: remaining);
      }

      if (owner.recoveryHash == null || owner.recoverySalt == null) {
        return RecoveryResult.invalidCode(
          message: 'No recovery code set up for this account',
        );
      }

      // Verifikasi recovery code (PBKDF2 + constant-time)
      final normalized = _normalizeRecoveryCode(recoveryCode);
      final isValid = _verifyRecoveryCode(
        normalized,
        owner.recoverySalt!,
        owner.recoveryHash!,
      );

      if (!isValid) {
        await _incrementRecoveryAttempts(owner.id);
        return RecoveryResult.invalidCode();
      }

      // Verifikasi lulus → generate kredensial baru dan TULIS SEKALI.
      // Kalau write gagal (storage penuh, dll), seluruh transaksi rollback —
      // owner tetap bisa pakai recovery code yang sama.
      final newSalt = CryptoUtils.generateSalt();
      final newPinHash = CryptoUtils.hashPin(newPin, newSalt);
      final newRecoveryCode = _generateRecoveryCode();
      final newRecoverySalt = _generateRecoverySalt();
      final newRecoveryHash =
          _hashRecoveryCode(newRecoveryCode, newRecoverySalt);

      await (_db.update(_db.users)..where((u) => u.id.equals(owner.id))).write(
        UsersCompanion(
          pinHash: Value(newPinHash),
          salt: Value(newSalt),
          recoveryHash: Value(newRecoveryHash),
          recoverySalt: Value(newRecoverySalt),
          recoveryCreatedAt: Value(DateTime.now()),
          recoveryUsedAt: Value(DateTime.now()),
          recoveryAttempts: const Value(0),
          recoveryLockedUntil: const Value(null),
        ),
      );

      return RecoveryResult.success(
        newRecoveryCode: newRecoveryCode,
        message: 'PIN reset successful',
      );
    });
  }

  /// Regenerate owner recovery code (requires current PIN)
  /// 
  /// Returns RecoveryResult with new recovery code if PIN correct
  Future<RecoveryResult> regenerateOwnerRecoveryCode(String currentPin) async {
    final owner = await _getOwner();
    if (owner == null) {
      return RecoveryResult.ownerNotFound();
    }

    // Verify current PIN
    final isValid = CryptoUtils.verifyPin(currentPin, owner.salt, owner.pinHash);
    if (!isValid) {
      return RecoveryResult.pinMismatch();
    }

    // Generate new recovery code
    final newRecoveryCode = await generateAndStoreRecoveryCodeForOwner(owner.id);

    return RecoveryResult.success(
      newRecoveryCode: newRecoveryCode,
      message: 'Recovery code regenerated',
    );
  }

  // ============================================================================
  // RECOVERY HELPER METHODS
  // ============================================================================

  /// Get owner user
  Future<User?> _getOwner() async {
    final owners = await (_db.select(_db.users)
          ..where((u) => u.role.equals('owner'))
          ..limit(1))
        .get();
    return owners.isNotEmpty ? owners.first : null;
  }

  /// Generate recovery code: XXXX-XXXX-XXXX-XXXX
  String _generateRecoveryCode() {
    // Use HashUtils from security package
    return HashUtils.generateRecoveryCode();
  }

  /// Normalize recovery code (remove dashes, spaces, uppercase)
  String _normalizeRecoveryCode(String code) {
    return HashUtils.normalizeRecoveryCode(code);
  }

  /// Generate salt for recovery code
  String _generateRecoverySalt() {
    return HashUtils.generateSalt();
  }

  /// Hash recovery code with salt
  String _hashRecoveryCode(String code, String salt) {
    return HashUtils.hashWithSalt(code, salt);
  }

  /// Verify recovery code
  bool _verifyRecoveryCode(String code, String salt, String hash) {
    return HashUtils.verifyWithSalt(code, salt, hash);
  }

  /// S5: Increment login attempts dan lock dengan exponential backoff yang sama
  /// dengan recovery (cycle 1=60s, 2=5min, 3=30min, 4=1h, 5+=24h).
  /// Pakai atomic SQL agar aman dari race condition.
  Future<void> _incrementLoginAttempts(String userId) async {
    await _db.customUpdate(
      'UPDATE users SET login_attempts = login_attempts + 1 WHERE id = ?',
      variables: [Variable.withString(userId)],
      updates: {_db.users},
    );

    final user = await getUserById(userId);
    if (user == null) return;

    if (user.loginAttempts > 0 && user.loginAttempts % 5 == 0) {
      final cycle = user.loginAttempts ~/ 5;
      final lockSeconds = _calculateLockSeconds(cycle);
      final lockUntil = DateTime.now().add(Duration(seconds: lockSeconds));
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(loginLockedUntil: Value(lockUntil)),
      );
    }
  }

  /// Format durasi lock untuk pesan error yang user-friendly.
  String _formatLockDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} jam';
    if (d.inMinutes >= 1) return '${d.inMinutes} menit';
    return '${d.inSeconds} detik';
  }

  /// Increment recovery attempts dan lock dengan exponential backoff.
  ///
  /// Setiap kelipatan 5 percobaan → lockout dengan durasi yang bertambah:
  /// - cycle 1 (attempts 5): 60 detik
  /// - cycle 2 (attempts 10): 5 menit
  /// - cycle 3 (attempts 15): 30 menit
  /// - cycle 4 (attempts 20): 1 jam
  /// - cycle 5+ (attempts 25+): 24 jam
  ///
  /// Increment pakai atomic SQL untuk fix race condition I2 (audit umum).
  Future<void> _incrementRecoveryAttempts(String userId) async {
    // Atomic increment — kalau 2 request paralel, keduanya tetap ke-count.
    await _db.customUpdate(
      'UPDATE users SET recovery_attempts = recovery_attempts + 1 WHERE id = ?',
      variables: [Variable.withString(userId)],
      updates: {_db.users},
    );

    final user = await getUserById(userId);
    if (user == null) return;

    // Setiap kelipatan 5 → lockout
    if (user.recoveryAttempts > 0 && user.recoveryAttempts % 5 == 0) {
      final cycle = user.recoveryAttempts ~/ 5;
      final lockSeconds = _calculateLockSeconds(cycle);
      final lockUntil = DateTime.now().add(Duration(seconds: lockSeconds));
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(recoveryLockedUntil: Value(lockUntil)),
      );
    }
  }

  /// Exponential backoff durasi lock berdasarkan cycle ke-berapa.
  int _calculateLockSeconds(int cycle) {
    switch (cycle) {
      case 1:
        return 60; // 1 menit
      case 2:
        return 300; // 5 menit
      case 3:
        return 1800; // 30 menit
      case 4:
        return 3600; // 1 jam
      default:
        return 86400; // 24 jam
    }
  }

  /// Reset recovery attempts
  Future<void> _resetRecoveryAttempts(String userId) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      const UsersCompanion(
        recoveryAttempts: Value(0),
        recoveryLockedUntil: Value(null),
      ),
    );
  }

  /// Reset recovery lock (saat lock expire).
  ///
  /// HANYA clear lockedUntil — JANGAN reset attempts.
  /// Counter attempts tetap dipertahankan untuk exponential backoff.
  Future<void> _resetRecoveryLock(String userId) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      const UsersCompanion(recoveryLockedUntil: Value(null)),
    );
  }
}
