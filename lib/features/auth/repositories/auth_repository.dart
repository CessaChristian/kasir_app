import 'package:drift/drift.dart';
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
      id: userId,
      username: username,
      pinHash: pinHash,
      salt: salt,
      role: 'owner',
      isActive: const Value(true),
    );

    await _db.into(_db.users).insert(ownerCompanion);

    // 6. Get and return the created user
    return await (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingle();
  }

  /// Login with username and PIN
  /// 
  /// Returns AuthSession if successful, null if credentials invalid
  Future<AuthSession?> login({
    required String username,
    required String pin,
  }) async {
    // 1. Find user by username
    final users = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .get();

    if (users.isEmpty) {
      return null; // User not found
    }

    final user = users.first;

    // 2. Check if user is active
    if (!user.isActive) {
      throw StateError('User account is deactivated');
    }

    // 3. Verify PIN
    final isValid = CryptoUtils.verifyPin(pin, user.salt, user.pinHash);
    if (!isValid) {
      return null; // Invalid PIN
    }

    // 4. Start a new shift
    final shiftId = await _startShift(user.id);

    // 5. Get user permissions
    final permissions = await _getUserPermissions(user.id, user.role);

    // 6. Create and return session
    return AuthSession(
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

  /// Get user by ID
  Future<User?> getUserById(String userId) async {
    final users =
        await (_db.select(_db.users)..where((u) => u.id.equals(userId))).get();
    return users.isNotEmpty ? users.first : null;
  }

  /// Start a new shift for a user
  /// Returns the shift ID
  Future<String> _startShift(String userId) async {
    final shiftId = _generateShiftId();

    await _db.into(_db.shifts).insert(
          ShiftsCompanion.insert(
            id: shiftId,
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

  /// Generate unique user ID
  String _generateUserId() {
    return 'user_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate unique shift ID
  String _generateShiftId() {
    return 'shift_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get all active usernames (for login dropdown)
  Future<List<String>> getAllActiveUsernames() async {
    final users = await (_db.select(_db.users)
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.username)]))
        .get();
    
    return users.map((u) => u.username).toList();
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

    // Valid - reset attempts
    await _resetRecoveryAttempts(owner.id);
    return RecoveryResult.success();
  }

  /// Reset owner PIN using valid recovery code
  /// 
  /// Auto-generates new recovery code after successful reset
  /// Returns RecoveryResult with new recovery code if successful
  Future<RecoveryResult> resetOwnerPinWithRecoveryCode({
    required String recoveryCode,
    required String newPin,
  }) async {
    // 1. Verify recovery code
    final verifyResult = await verifyOwnerRecoveryCode(recoveryCode);
    if (!verifyResult.isSuccess) {
      return verifyResult;
    }

    // 2. Validate new PIN format
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      return RecoveryResult.invalidCode(
        message: 'New PIN must be 4-6 digits',
      );
    }

    final owner = await _getOwner();
    if (owner == null) {
      return RecoveryResult.ownerNotFound();
    }

    // 3. Generate new PIN hash
    final newSalt = CryptoUtils.generateSalt();
    final newPinHash = CryptoUtils.hashPin(newPin, newSalt);

    // 4. Generate new recovery code (old one is compromised)
    final newRecoveryCode = _generateRecoveryCode();
    final newRecoverySalt = _generateRecoverySalt();
    final newRecoveryHash = _hashRecoveryCode(newRecoveryCode, newRecoverySalt);

    // 5. Update owner
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

  /// Increment recovery attempts and lock if >= 5
  Future<void> _incrementRecoveryAttempts(String userId) async {
    final user = await getUserById(userId);
    if (user == null) return;

    final newAttempts = user.recoveryAttempts + 1;

    if (newAttempts >= 5) {
      // Lock for 60 seconds
      final lockUntil = DateTime.now().add(const Duration(seconds: 60));
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          recoveryAttempts: Value(newAttempts),
          recoveryLockedUntil: Value(lockUntil),
        ),
      );
    } else {
      await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          recoveryAttempts: Value(newAttempts),
        ),
      );
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

  /// Reset recovery lock
  Future<void> _resetRecoveryLock(String userId) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      const UsersCompanion(
        recoveryAttempts: Value(0),
        recoveryLockedUntil: Value(null),
      ),
    );
  }
}
