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
}
