import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/uuid_helper.dart';
import '../../../utils/crypto_utils.dart';
import '../../../shared/auth/session_manager.dart';

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
  /// S11: All mutating methods require manage_cashiers permission.
  void _requireManageCashiers() {
    SessionManager.instance.requirePermission('manage_cashiers');
  }

  Future<User> createCashier({
    required String username,
    required String pin,
  }) async {
    _requireManageCashiers();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(pin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
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

    // 4. Primary key WAJIB UUID supaya unik lintas device saat sync.
    final userId = newUuid();

    // I1: Bungkus insert user + set permissions dalam satu transaksi.
    // Kalau permissions gagal di-set, user juga di-rollback agar tidak
    // ada akun "zombie" tanpa permission.
    return await _db.transaction<User>(() async {
      await _db.into(_db.users).insert(
            UsersCompanion.insert(
              id: Value(userId),
              username: username,
              pinHash: pinHash,
              salt: salt,
              role: 'cashier',
              isActive: const Value(true),
            ),
          );

      await _setDefaultCashierPermissions(userId);

      final created = await (_db.select(_db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (created == null) {
        throw StateError(
            'Akun kasir berhasil dibuat. Kasir dapat login menggunakan username dan PIN yang baru.');
      }
      return created;
    });
  }

  /// Semua akun kasir, terbaru dulu.
  Future<List<User>> getAllCashiers() async {
    return await (_db.select(_db.users)
          ..where((u) => u.role.equals('cashier'))
          ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]))
        .get();
  }

  /// Toggle cashier active status
  Future<void> toggleCashierStatus(String userId, bool isActive) async {
    _requireManageCashiers();
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Reset cashier PIN
  Future<void> resetCashierPin(String userId, String newPin) async {
    _requireManageCashiers();

    // 1. Validate PIN format
    if (!CryptoUtils.isValidPinFormat(newPin)) {
      throw ArgumentError('PIN harus ${CryptoUtils.pinLength} digit angka');
    }

    // 2. Generate new salt and hash
    final salt = CryptoUtils.generateSalt();
    final pinHash = CryptoUtils.hashPin(newPin, salt);

    // 3. Update user
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        salt: Value(salt),
        pinHash: Value(pinHash),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
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

}
