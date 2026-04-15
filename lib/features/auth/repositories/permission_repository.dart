import 'package:drift/drift.dart';
import '../../../data/app_database.dart';

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
  Future<void> setUserPermission({
    required String userId,
    required String permissionCode,
    required bool enabled,
  }) async {
    await _db.into(_db.userPermissions).insertOnConflictUpdate(
          UserPermissionsCompanion.insert(
            userId: userId,
            permissionCode: permissionCode,
            enabled: Value(enabled),
          ),
        );
  }

  /// Set multiple permissions for a user at once
  Future<void> setUserPermissions({
    required String userId,
    required Map<String, bool> permissions,
  }) async {
    await Future.wait(
      permissions.entries.map((entry) => setUserPermission(
            userId: userId,
            permissionCode: entry.key,
            enabled: entry.value,
          )),
    );
  }

  /// Get list of enabled permission codes for a user
  Future<List<String>> getEnabledPermissions(String userId) async {
    final userPerms = await (_db.select(_db.userPermissions)
          ..where((up) => up.userId.equals(userId))
          ..where((up) => up.enabled.equals(true)))
        .get();

    return userPerms.map((up) => up.permissionCode).toList();
  }
}
