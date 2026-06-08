import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/business_context.dart';
import '../../data/db.dart';
import '../../features/auth/models/auth_session.dart';

/// Singleton untuk manajemen authentication session.
///
/// Session di-cache in-memory + persist ke SharedPreferences.
/// PENTING: `role` dan `permissions` dari storage TIDAK dipercaya;
/// SessionManager re-validate ke DB saat `restoreSession()` untuk
/// mencegah privilege escalation via tamper SharedPreferences (S6).
///
/// Session expire setelah 12 jam (S7).
class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  static const String _sessionKey = 'auth_session';

  AuthSession? _currentSession;

  /// Set the current session dan persist ke storage.
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, json.encode(session.toJson()));
  }

  /// Clear current session.
  Future<void> clearSession() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    BusinessContext.instance.clear();
  }

  /// Restore session dari storage.
  ///
  /// Flow validasi:
  /// 1. Baca JSON dari SharedPreferences
  /// 2. Cek expiration (S7) — kalau expired → clear
  /// 3. Re-query user dari DB (S6) — kalau hilang/nonaktif → clear
  /// 4. Overwrite `role` dan `permissions` dari DB — TIDAK percaya nilai di storage
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString(_sessionKey);

    if (sessionJson == null) return;

    AuthSession session;
    try {
      final sessionMap = json.decode(sessionJson) as Map<String, dynamic>;
      session = AuthSession.fromJson(sessionMap);
    } catch (_) {
      await clearSession();
      return;
    }

    // S7: cek expiration
    if (session.isExpired) {
      await clearSession();
      return;
    }

    // S6: re-validate user dari DB — JANGAN percaya role/permissions di storage
    try {
      final user = await (db.select(db.users)
            ..where((u) => u.id.equals(session.userId))
            ..limit(1))
          .getSingleOrNull();

      if (user == null || !user.isActive) {
        // User dihapus atau dinonaktifkan setelah session dibuat
        await clearSession();
        return;
      }

      // Refresh permissions dari DB
      final freshPermissions = await _getUserPermissionsFromDb(user.id, user.role);

      // Overwrite role + permissions dengan nilai DB (anti-tamper)
      _currentSession = session.copyWith(
        role: user.role,
        permissions: freshPermissions,
      );

      // Sinkronkan storage agar konsisten dengan DB
      await prefs.setString(_sessionKey, json.encode(_currentSession!.toJson()));

      // Multi-business: re-populate BusinessContext + role cache
      try {
        await BusinessContext.instance.loadInitial(userId: user.id);
        await refreshRoleCache();
      } catch (_) {
        // Tidak clear session — biarkan session restore, hanya warn
        // (BusinessContext null akan di-handle di UI layer)
      }
    } catch (_) {
      // DB error saat restore → clear session, user perlu login ulang
      await clearSession();
    }
  }

  /// Helper: ambil permissions dari DB.
  Future<List<String>> _getUserPermissionsFromDb(
      String userId, String role) async {
    if (role == 'owner') {
      final all = await db.select(db.permissions).get();
      return all.map((p) => p.code).toList();
    }
    final perms = await (db.select(db.userPermissions)
          ..where((up) => up.userId.equals(userId))
          ..where((up) => up.enabled.equals(true)))
        .get();
    return perms.map((p) => p.permissionCode).toList();
  }

  AuthSession? get currentSession => _currentSession;
  bool get isLoggedIn => _currentSession != null;
  bool get isOwner => _currentSession?.isOwner ?? false;
  bool get isCashier => _currentSession?.isCashier ?? false;

  /// Check permission. Owner always returns true.
  bool hasPermission(String permissionCode) {
    if (_currentSession == null) return false;
    if (_currentSession!.isOwner) return true;
    return _currentSession!.permissions.contains(permissionCode);
  }

  void requireLoggedIn() {
    if (!isLoggedIn) throw StateError('User must be logged in');
  }

  void requireOwner() {
    requireLoggedIn();
    if (!isOwner) throw StateError('Owner access required');
  }

  void requirePermission(String permissionCode) {
    requireLoggedIn();
    if (!hasPermission(permissionCode)) {
      throw StateError('Permission required: $permissionCode');
    }
  }

  String? get currentUserId => _currentSession?.userId;
  String? get currentShiftId => _currentSession?.shiftId;
  String? get currentUsername => _currentSession?.username;

  // =====================================
  // Context-aware permission (Phase 1 multi-business)
  // =====================================

  /// Hardcoded permission matrix per role (sesuai spec §5.3.2).
  /// Future: pindahkan ke DB kalau butuh runtime override per-user.
  static const _rolePermissions = <String, Set<String>>{
    'owner': {
      'view_dashboard', 'manage_products', 'manage_categories',
      'view_all_expenses', 'edit_own_expense', 'edit_any_expense',
      'delete_own_transaction', 'delete_any_transaction',
      'view_shift_reports', 'view_all_shifts',
      'manage_business', 'manage_cashiers', 'switch_business',
      // Existing permissions (backward compat)
      'open_close_shift', 'create_transaction', 'view_history', 'view_report',
    },
    'cashier': {
      'view_dashboard',
      'edit_own_expense',
      'delete_own_transaction',
      // Existing permissions (backward compat)
      'open_close_shift', 'create_transaction', 'view_history',
    },
  };

  /// In-memory cache role per business untuk current user.
  /// Di-populate via [refreshRoleCache] setelah login + setelah switch business.
  final Map<String, String> _roleCache = {};

  /// Check permission di context BusinessContext.instance.activeBusinessId.
  /// Return false kalau no active business atau user tidak punya role.
  bool hasCurrentPermission(String permission) {
    if (_currentSession == null) return false;

    final businessId = BusinessContext.instance.activeBusinessId;
    if (businessId == null) return false;

    // Sync read role dari _roleCache (populated by refreshRoleCache setelah login)
    final role = _roleCache[businessId];
    if (role == null) return false; // belum di-cache, panggil refreshRoleCache dulu

    return _rolePermissions[role]?.contains(permission) ?? false;
  }

  /// Throw kalau no permission. Pakai ini di UI handler.
  void requireCurrentPermission(String permission) {
    if (!hasCurrentPermission(permission)) {
      throw StateError('Permission required (current business): $permission');
    }
  }

  /// Refresh role cache untuk current user dari DB.
  /// Wajib dipanggil setelah:
  /// - Login sukses
  /// - BusinessContext.switchTo (business baru)
  /// - Add/remove user_business_role (jarang, biasanya saat onboarding)
  Future<void> refreshRoleCache() async {
    _roleCache.clear();
    if (_currentSession == null) return;

    final userId = _currentSession!.userId;
    final roles = await (db.select(db.userBusinessRoles)
          ..where((r) => r.userId.equals(userId))
          ..where((r) => r.deletedAt.isNull()))
        .get();

    for (final role in roles) {
      _roleCache[role.businessId] = role.role;
    }
  }

  /// Helper untuk dual check pattern (edit/delete own data).
  /// Return true kalau:
  /// - User punya permission `*_any_*` (owner override), ATAU
  /// - User punya permission `*_own_*` AND recordOwnerId == currentUserId
  bool canPerformActionOnRecord({
    required String anyPermission,
    required String ownPermission,
    required String? recordOwnerId,
  }) {
    if (hasCurrentPermission(anyPermission)) return true;
    if (hasCurrentPermission(ownPermission) &&
        recordOwnerId == _currentSession?.userId) {
      return true;
    }
    return false;
  }
}
