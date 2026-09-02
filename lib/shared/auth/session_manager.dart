import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/app_database.dart';
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

  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

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
      final user = await (_dbx.select(_dbx.users)
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
    } catch (_) {
      // DB error saat restore → clear session, user perlu login ulang
      await clearSession();
    }
  }

  /// Helper: ambil permissions dari DB.
  Future<List<String>> _getUserPermissionsFromDb(
      String userId, String role) async {
    if (role == 'owner') {
      final all = await _dbx.select(_dbx.permissions).get();
      return all.map((p) => p.code).toList();
    }
    final perms = await (_dbx.select(_dbx.userPermissions)
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

  /// Permission menurut role user yang sedang login.
  ///
  /// Dulu role dibaca dari cache per-business yang diisi dari
  /// `user_business_roles` — sumber kebenaran kedua di samping `users.role`.
  /// Duplikasi itu dibuang di v13; role sekarang hanya ada satu tempat,
  /// yaitu `users.role` yang sudah divalidasi ulang dari DB saat
  /// [restoreSession] (anti-tamper).
  bool hasCurrentPermission(String permission) {
    final role = _currentSession?.role;
    if (role == null) return false;
    return _rolePermissions[role]?.contains(permission) ?? false;
  }

  /// Throw kalau no permission. Pakai ini di UI handler.
  void requireCurrentPermission(String permission) {
    if (!hasCurrentPermission(permission)) {
      throw StateError('Permission required: $permission');
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
