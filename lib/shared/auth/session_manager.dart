import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/auth_session.dart';

/// Singleton class for managing authentication session
/// 
/// Stores session in-memory for fast access and persists to
/// SharedPreferences for cross-app-restart persistence
class SessionManager {
  static final SessionManager instance = SessionManager._();
  SessionManager._();

  static const String _sessionKey = 'auth_session';

  AuthSession? _currentSession;

  /// Set the current session and persist to storage
  Future<void> setSession(AuthSession session) async {
    _currentSession = session;
    
    // Persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, json.encode(session.toJson()));
  }

  /// Clear the current session
  Future<void> clearSession() async {
    _currentSession = null;
    
    // Clear from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Try to restore session from SharedPreferences
  /// 
  /// Call this on app start to restore previous session
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString(_sessionKey);

    if (sessionJson != null) {
      try {
        final sessionMap = json.decode(sessionJson) as Map<String, dynamic>;
        _currentSession = AuthSession.fromJson(sessionMap);
      } catch (e) {
        // If restore fails, clear invalid session
        await clearSession();
      }
    }
  }

  /// Get current session (can be null if not logged in)
  AuthSession? get currentSession => _currentSession;

  /// Check if user is currently logged in
  bool get isLoggedIn => _currentSession != null;

  /// Check if current user is owner
  bool get isOwner => _currentSession?.isOwner ?? false;

  /// Check if current user is cashier
  bool get isCashier => _currentSession?.isCashier ?? false;

  /// Check if current user has a specific permission
  /// 
  /// Owners always return true for any permission
  /// Cashiers: returns true only if permission is in their enabled list
  bool hasPermission(String permissionCode) {
    if (_currentSession == null) return false;
    if (_currentSession!.isOwner) return true; // Owner has all permissions
    return _currentSession!.permissions.contains(permissionCode);
  }

  /// Require that user is logged in
  /// 
  /// Throws StateError if not logged in
  void requireLoggedIn() {
    if (!isLoggedIn) {
      throw StateError('User must be logged in');
    }
  }

  /// Require that user is owner
  /// 
  /// Throws StateError if not owner
  void requireOwner() {
    requireLoggedIn();
    if (!isOwner) {
      throw StateError('Owner access required');
    }
  }

  /// Require specific permission
  /// 
  /// Throws StateError if user doesn't have the permission
  void requirePermission(String permissionCode) {
    requireLoggedIn();
    if (!hasPermission(permissionCode)) {
      throw StateError('Permission required: $permissionCode');
    }
  }

  /// Get the current user's ID
  String? get currentUserId => _currentSession?.userId;

  /// Get the current shift ID
  String? get currentShiftId => _currentSession?.shiftId;

  /// Get the current username
  String? get currentUsername => _currentSession?.username;
}
