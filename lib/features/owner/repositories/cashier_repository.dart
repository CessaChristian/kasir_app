import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../utils/crypto_utils.dart';

/// Repository for managing cashier accounts
class CashierRepository {
  final AppDatabase _db;

  CashierRepository(this._db);

  /// Create a new cashier account with default permissions
  /// 
  /// Default permissions for cashiers:
  /// - open_close_shift: true
  /// - create_transaction: true
  /// - view_history: true
  /// - view_report: false
  /// - manage_products: false
  /// - manage_cashiers: false
  Future<User> createCashier({
    required String username,
    required String pin,
  }) async {
    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN must be 4-6 digits');
    }

    // 2. Check if username already exists
    final existing = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .get();

    if (existing.isNotEmpty) {
      throw StateError('Username already exists');
    }

    // 3. Generate salt and hash PIN
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(pin, salt);

    // 4. Generate unique ID
    final userId = _generateUserId();

    // 5. Create cashier account
    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            id: userId,
            username: username,
            pinHash: pinHash,
            salt: salt,
            role: 'cashier',
            isActive: const Value(true),
          ),
        );

    // 6. Set default permissions
    await _setDefaultCashierPermissions(userId);

    // 7. Get and return the created user
    return await (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingle();
  }

  /// Get all cashiers
  Future<List<User>> getAllCashiers() async {
    return await (_db.select(_db.users)
          ..where((u) => u.role.equals('cashier'))
          ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]))
        .get();
  }

  /// Toggle cashier active status
  Future<void> toggleCashierStatus(String userId, bool isActive) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        isActive: Value(isActive),
      ),
    );
  }

  /// Reset cashier PIN
  Future<void> resetCashierPin(String userId, String newPin) async {
    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      throw ArgumentError('PIN must be 4-6 digits');
    }

    // 2. Generate new salt and hash
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(newPin, salt);

    // 3. Update user
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        salt: Value(salt),
        pinHash: Value(pinHash),
      ),
    );
  }

  /// Set default permissions for a new cashier
  Future<void> _setDefaultCashierPermissions(String userId) async {
    final defaultPermissions = {
      'open_close_shift': true,
      'create_transaction': true,
      'view_history': true,
      'view_report': false,
      'manage_products': false,
      'manage_cashiers': false,
    };

    for (final entry in defaultPermissions.entries) {
      await _db.into(_db.userPermissions).insert(
            UserPermissionsCompanion.insert(
              userId: userId,
              permissionCode: entry.key,
              enabled: Value(entry.value),
            ),
          );
    }
  }

  /// Generate unique user ID
  String _generateUserId() {
    return 'cashier_${DateTime.now().millisecondsSinceEpoch}';
  }
}
