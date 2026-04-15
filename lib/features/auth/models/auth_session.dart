/// Authentication session model
/// 
/// Represents the current authenticated user's session including
/// their permissions and active shift
class AuthSession {
  final String userId;
  final String username;
  final String role; // 'owner' or 'cashier'
  final String shiftId;
  final List<String> permissions; // List of enabled permission codes

  const AuthSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.shiftId,
    required this.permissions,
  });

  /// Check if user is owner
  bool get isOwner => role == 'owner';

  /// Check if user is cashier
  bool get isCashier => role == 'cashier';

  /// Convert to JSON for SharedPreferences storage
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'role': role,
      'shiftId': shiftId,
      'permissions': permissions,
    };
  }

  /// Create from JSON
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: json['userId'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      shiftId: json['shiftId'] as String,
      permissions: List<String>.from(json['permissions'] as List),
    );
  }

  @override
  String toString() => 'AuthSession(userId: $userId, username: $username, role: $role, shiftId: $shiftId)';
}
