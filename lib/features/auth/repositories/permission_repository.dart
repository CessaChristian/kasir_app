import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/auth/session_manager.dart';

/// Repository for managing user permissions
class PermissionRepository {
  final AppDatabase _db;

  PermissionRepository(this._db);

  /// Get all available permissions
  Future<List<Permission>> getAllPermissions() async {
    return await _db.select(_db.permissions).get();
  }

  /// Get user's permissions with their enabled status
  /// 
  /// Returns a map of permission code to enabled status
  Future<Map<String, bool>> getUserPermissions(String userId) async {
    final userPerms = await (_db.select(_db.userPermissions)
          ..where((up) => up.userId.equals(userId)))
        .get();

    return {
      for (final up in userPerms) up.permissionCode: up.enabled,
    };
  }

  /// Set a specific permission for a user
  ///
  /// Hanya owner. Dulu cuma halamannya yang disembunyikan dari kasir.
  Future<void> setUserPermission({
    required String userId,
    required String permissionCode,
    required bool enabled,
  }) async {
    SessionManager.instance.requireOwner();
    await _tulisIzin(userId, permissionCode, enabled);
  }

  Future<void> _tulisIzin(
    String userId,
    String permissionCode,
    bool enabled,
  ) async {
    // `id` turunan, bukan acak: identitas baris ini adalah pasangan
    // (user, izin) itu sendiri. Kalau acak, HP owner dan HP kasir yang
    // sama-sama menyetel izin yang sama menghasilkan dua baris berbeda, dan
    // yang kedua ditolak batasan unik lalu tertahan selamanya saat sync.
    await _db.into(_db.userPermissions).insertOnConflictUpdate(
          UserPermissionsCompanion.insert(
            id: uuidTurunan('$userId:$permissionCode'),
            userId: userId,
            permissionCode: permissionCode,
            enabled: Value(enabled),
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value('pending'),
          ),
        );
  }

  /// Set multiple permissions for a user at once
  ///
  /// Satu transaksi: semua izin tersimpan atau tidak sama sekali. Dulu
  /// disimpan satu per satu, jadi kegagalan di tengah meninggalkan izin
  /// setengah jadi.
  Future<void> setUserPermissions({
    required String userId,
    required Map<String, bool> permissions,
  }) async {
    SessionManager.instance.requireOwner();
    await _db.transaction(() async {
      for (final entry in permissions.entries) {
        await _tulisIzin(userId, entry.key, entry.value);
      }
    });
  }
}
