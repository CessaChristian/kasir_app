import 'dart:async';
import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/uuid_helper.dart';
import '../../../utils/crypto_utils.dart';
import '../../../utils/security/hash_utils.dart';
import '../recovery/models/recovery_result.dart';
import '../models/auth_session.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../data/perangkat/perangkat_repository.dart';

/// Repository for authentication operations
class AuthRepository {
  final AppDatabase _db;

  /// Diisi test untuk [logout]. Bawaan: [SyncService.tungguSelesai] dan
  /// [PerangkatRepository.hadir].
  final Future<void> Function()? _tungguSinkron;
  final Future<void> Function(String? shiftId)? _lapor;

  AuthRepository(
    this._db, {
    Future<void> Function()? tungguSinkron,
    Future<void> Function(String? shiftId)? lapor,
  }) : _tungguSinkron = tungguSinkron,
       _lapor = lapor;

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
      throw StateError('Akun owner sudah ada.');
    }

    // 2. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }

    // 3. Generate salt and hash PIN
    final salt = CryptoUtils.generateSalt();
    final pinHash = await CryptoUtils.hashPinDiLatar(pin, salt);

    // 4. Primary key WAJIB UUID supaya unik lintas device saat sync.
    final userId = newUuid();

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

    // 2. Akun dihapus (username-nya sudah diganti, jadi praktis tak
    // tertemukan — ini jaring kedua) atau dinonaktifkan.
    if (user.deletedAt != null) {
      throw StateError('Akun Anda sudah dihapus oleh pemilik.');
    }
    if (!user.isActive) {
      throw StateError('Akun Anda dinonaktifkan oleh pemilik.');
    }

    // 2b. S5: Cek apakah akun sedang ter-lock karena terlalu banyak gagal login.
    if (user.loginLockedUntil != null &&
        user.loginLockedUntil!.isAfter(DateTime.now())) {
      final remaining = user.loginLockedUntil!.difference(DateTime.now());
      throw StateError(
          'Akun terkunci. Coba lagi dalam ${_formatLockDuration(remaining)}.');
    }

    // 3. Verify PIN — di isolate lain supaya tombol "Memeriksa…" langsung
    // tampil dan layar tidak macet selama PBKDF2 berjalan.
    final isValid =
        await CryptoUtils.verifyPinDiLatar(pin, user.salt, user.pinHash);
    if (!isValid) {
      // S5: Increment login attempts + lockout dengan exponential backoff.
      await _incrementLoginAttempts(user.id);
      return null;
    }

    // S5: PIN benar → reset login attempts + clear lock.
    if (user.loginAttempts > 0 || user.loginLockedUntil != null) {
      // updatedAt SENGAJA tidak dinaikkan. Counter rate-limit bersifat
      // device-local: menaikkannya membuat baris user terlihat "lebih baru"
      // setiap kali salah ketik PIN, sehingga bisa menimpa perubahan sah dari
      // device lain saat sync. Lihat catatan yang sama di _lockUser().
      await (_db.update(_db.users)..where((u) => u.id.equals(user.id)))
          .write(const UsersCompanion(
        loginAttempts: Value(0),
        loginLockedUntil: Value(null),
      ));
    }

    // 3b. Migrasi transparan: kalau hash masih format lama (SHA-256),
    // re-hash dengan PBKDF2 dan update DB.
    if (CryptoUtils.needsRehash(user.pinHash)) {
      final newHash = await CryptoUtils.hashPinDiLatar(pin, user.salt);
      await (_db.update(_db.users)..where((u) => u.id.equals(user.id)))
          .write(UsersCompanion(
        pinHash: Value(newHash),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));
    }

    // 4. Lanjutkan shift yang masih berjalan — HANYA untuk kasir. Sejak v37
    // login TIDAK membuka shift: kasir membukanya sendiri lewat "Buka shift"
    // sambil mencatat kas awal (keputusan owner 2026-10-13). Owner tidak
    // menjalankan shift sama sekali.
    final shiftId =
        user.role == 'owner' ? null : await cariShiftTerbuka(user.id);

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

  /// Keluar dari akun. Shift yang sedang berjalan SENGAJA tidak ditutup:
  /// kasir yang cuma gantian memegang HP harus bisa keluar tanpa mematikan
  /// shiftnya, dan bisa melanjutkannya setelah masuk lagi. Menutup shift
  /// adalah perbuatan terpisah — "Tutup shift" di Profil.
  Future<void> logout() async {
    // Lepaskan tanda "perangkat ini memegang shift X" di server.
    //
    // Tanpa ini, perangkat yang sudah keluar tetap tercatat memegang shiftnya,
    // dan perangkat lain akan ditolak saat hendak menutup shift itu — ditahan
    // oleh HP yang bahkan tidak ada yang memegangnya.
    //
    // ── URUTANNYA PENTING ──
    //
    // Sinkron juga melapor ke server di akhir putarannya, membawa shift dari
    // sesi. Dulu tanda dilepas DULU baru sesi dihapus, sehingga sinkron yang
    // sedang berjalan bisa melapor sesudahnya dan memasang shiftnya lagi —
    // dugaan kuat kenapa emulator yang sudah keluar tetap tercatat memegang
    // shift (2026-10-17). Sekarang: sesi dihapus (laporan berikutnya membawa
    // "tanpa shift"), putaran yang sedang jalan ditunggu, baru tanda dilepas
    // — laporan terakhir yang sampai pasti "tanpa shift".
    //
    // Best-effort: `hadir` menelan galatnya sendiri. Kalau sedang offline,
    // tandanya baru terlepas saat perangkat ini online lagi. Keluar dari akun
    // tidak boleh gagal hanya karena jaringannya mati.
    await SessionManager.instance.clearSession();
    await laporShift(null);
  }

  /// Beri tahu server shift yang dipegang perangkat ini SEKARANG — sesudah
  /// login melanjutkan shift, membuka shift, atau keluar (null).
  ///
  /// Tanpa ini server baru tahu pada sinkron berikutnya (sampai 5 menit),
  /// dan selama itu perangkat lain bisa menutup shift yang baru saja
  /// dimasuki di sini.
  ///
  /// Sinkron yang sedang berjalan ditunggu DULU: ia ikut melapor di akhir
  /// putarannya, membawa shift yang dibacanya dari sesi sebelum berubah.
  /// Kalau laporannya tiba belakangan, shift yang lama terpasang lagi.
  /// Panggil SESUDAH sesinya diubah.
  Future<void> laporShift(String? shiftId) async {
    await (_tungguSinkron ?? SyncService.instance.tungguSelesai)();
    await (_lapor ?? PerangkatRepository.instance.hadir)(shiftId);
  }

  Future<User?> getUserById(String userId) {
    return (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
  }

  /// Berapa lama menunggu server sebelum login dilanjutkan tanpanya.
  ///
  /// Login TIDAK BOLEH gagal atau menggantung hanya karena jaringannya lambat:
  /// warung harus tetap bisa melayani saat internet mati.
  static const _jedaTungguShift = Duration(seconds: 4);

  /// Shift yang masih berjalan milik [userId], atau null.
  ///
  /// Dipakai saat login (melanjutkan shift) dan sebelum membuka shift baru
  /// (supaya tidak lahir shift kedua untuk orang yang sama).
  ///
  /// ── KENAPA SERVER DITANYA DULU ──
  ///
  /// Kalau yang dilihat hanya database LOKAL, kasir yang sama di HP kedua
  /// tidak tahu shift buatan HP pertama, lalu membuka shift KEDUA. Akibatnya
  /// transaksinya terpecah ke dua shift dan rekapnya tidak bisa dipercaya.
  /// Menariknya lebih dulu menutup kasus yang paling sering: dua HP sama-sama
  /// online, kasir berpindah HP.
  Future<String?> cariShiftTerbuka(String userId) async {
    await _tarikShiftDariServer();

    // Urutannya WAJIB pasti. Tanpa `orderBy`, kalau ada dua shift terbuka,
    // yang terpilih mengikuti urutan penyimpanan — dan itu bisa berbeda di
    // tiap HP, sehingga dua perangkat memakai shift yang berbeda walau
    // datanya sudah sama persis. Yang paling awal dimulai dipilih di mana pun.
    final terbuka = await (_db.select(_db.shifts)
          ..where((s) =>
              s.userId.equals(userId) &
              s.endAt.isNull() &
              s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.startAt)]))
        .get();
    if (terbuka.isEmpty) return null;

    await _tutupShiftHantu(terbuka.skip(1));
    return terbuka.first.id;
  }

  /// Menarik tabel `shifts` dari server, sebisanya.
  ///
  /// Gagal DIABAIKAN dengan sengaja. Internet mati, server lambat, perangkat
  /// baru dicabut — apa pun sebabnya, kasir tetap harus bisa masuk dan
  /// melayani. Kalau tarikannya tidak jadi, keputusannya cukup memakai data
  /// lokal seperti sebelumnya; paling buruk lahir shift kedua, dan itu
  /// disatukan sendiri saat login berikutnya.
  Future<void> _tarikShiftDariServer() async {
    try {
      if (!SupabaseService.instance.online) return;
      await SyncEngine(_db).tarikTabel('shifts').timeout(_jedaTungguShift);
    } catch (_) {
      // Sengaja dibisukan — lihat catatan di atas.
    }
  }

  /// Menutup shift terbuka yang KOSONG dan bukan yang sedang dipakai.
  ///
  /// ── KENAPA HANYA YANG KOSONG ──
  ///
  /// Shift yang sudah dipakai jualan TIDAK disentuh, karena dua hal: HP lain
  /// mungkin masih aktif memakainya, dan angkanya sudah masuk laporan. Menutup
  /// shift berisi dari belakang layar berarti mengubah pembukuan tanpa ada
  /// yang memintanya.
  ///
  /// Yang kosong tidak punya risiko itu — tidak ada yang bisa salah hitung
  /// dari shift tanpa satu pun catatan. Dan justru yang kosong inilah yang
  /// menggantung "Berlangsung" selamanya di halaman Pengeluaran pemilik.
  Future<void> _tutupShiftHantu(Iterable<Shift> lain) async {
    for (final s in lain) {
      final adaTransaksi = await (_db.select(_db.transactions)
            ..where((t) => t.shiftId.equals(s.id) & t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (adaTransaksi != null) continue;

      final adaPengeluaran = await (_db.select(_db.expenses)
            ..where((e) => e.shiftId.equals(s.id) & e.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (adaPengeluaran != null) continue;

      final sekarang = DateTime.now();
      await (_db.update(_db.shifts)..where((t) => t.id.equals(s.id))).write(
        ShiftsCompanion(
          endAt: Value(sekarang),
          updatedAt: Value(sekarang),
          syncStatus: const Value('pending'),
        ),
      );
    }
  }

  /// Get user permissions
  /// 
  /// For owners, returns all permission codes (always full access)
  /// For cashiers, returns only enabled permissions
  Future<List<String>> _getUserPermissions(String userId, String role) async {
    // Owner has all permissions KECUALI yang memang bukan haknya —
    // menjual dan membuka shift. Lihat SessionManager.izinBukanUntukOwner.
    if (role == 'owner') {
      final allPermissions = await _db.select(_db.permissions).get();
      return allPermissions
          .map((p) => p.code)
          .where((k) => !SessionManager.izinBukanUntukOwner.contains(k))
          .toList();
    }

    // Cashier: get enabled permissions only
    final userPerms = await (_db.select(_db.userPermissions)
          ..where((up) => up.userId.equals(userId))
          ..where((up) => up.enabled.equals(true)))
        .get();

    return userPerms.map((up) => up.permissionCode).toList();
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
      throw StateError('Akun ini bukan owner.');
    }

    // Generate recovery code (formatted with dashes)
    final recoveryCode = _generateRecoveryCode();
    
    // Normalize for hashing (remove dashes)
    final normalizedCode = _normalizeRecoveryCode(recoveryCode);

    // Generate salt and hash
    final salt = _generateRecoverySalt();
    final hash = await _hashRecoveryCode(normalizedCode, salt);

    // Update owner with recovery data
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        recoveryHash: Value(hash),
        recoverySalt: Value(salt),
        recoveryCreatedAt: Value(DateTime.now()),
        recoveryUsedAt: const Value(null),
        recoveryAttempts: const Value(0),
        recoveryLockedUntil: const Value(null),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
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
        message: 'PIN baru harus 6 digit angka',
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
      final isValid = await _verifyRecoveryCode(
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
      final newPinHash = await CryptoUtils.hashPinDiLatar(newPin, newSalt);
      final newRecoveryCode = _generateRecoveryCode();
      final newRecoverySalt = _generateRecoverySalt();
      final newRecoveryHash =
          await _hashRecoveryCode(newRecoveryCode, newRecoverySalt);

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
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
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
    final isValid = await CryptoUtils.verifyPinDiLatar(
      currentPin,
      owner.salt,
      owner.pinHash,
    );
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
  Future<String> _hashRecoveryCode(String code, String salt) {
    return HashUtils.hashWithSaltDiLatar(code, salt);
  }

  /// Verify recovery code
  Future<bool> _verifyRecoveryCode(String code, String salt, String hash) {
    return HashUtils.verifyWithSaltDiLatar(code, salt, hash);
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
      // updatedAt SENGAJA tidak dinaikkan — kunci login bersifat device-local.
      // Menyinkronkannya berarti salah ketik PIN di satu HP ikut mengunci akun
      // di semua HP, dan membuat baris user selalu terlihat paling baru
      // sehingga menimpa perubahan sah dari device lain.
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
      // updatedAt sengaja tidak dinaikkan — device-local, sama seperti _lockUser().
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

  /// Reset recovery lock (saat lock expire).
  ///
  /// HANYA clear lockedUntil — JANGAN reset attempts.
  /// Counter attempts tetap dipertahankan untuk exponential backoff.
  Future<void> _resetRecoveryLock(String userId) async {
    // updatedAt sengaja tidak dinaikkan — device-local, sama seperti _lockUser().
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      const UsersCompanion(recoveryLockedUntil: Value(null)),
    );
  }
}
