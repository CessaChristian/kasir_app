/// Authentication session model.
///
/// `role` dan `permissions` di-deserialize dari storage TIDAK pernah
/// dipercaya — SessionManager akan re-validate dari DB pada restore untuk
/// mencegah privilege escalation via tamper SharedPreferences (S6).
///
/// `expiresAt` = session kadaluarsa setelah 12 jam (typical shift length).
class AuthSession {
  final String userId;
  final String username;
  final String role; // 'owner' atau 'cashier'
  final String shiftId;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime expiresAt;

  const AuthSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.shiftId,
    required this.permissions,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Default session: kadaluarsa 12 jam dari sekarang.
  factory AuthSession.create({
    required String userId,
    required String username,
    required String role,
    required String shiftId,
    required List<String> permissions,
  }) {
    final now = DateTime.now();
    return AuthSession(
      userId: userId,
      username: username,
      role: role,
      shiftId: shiftId,
      permissions: permissions,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 12)),
    );
  }

  bool get isOwner => role == 'owner';
  bool get isCashier => role == 'cashier';

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Copy dengan field baru — dipakai SessionManager saat re-validate dari DB.
  AuthSession copyWith({
    String? role,
    List<String>? permissions,
    String? shiftId,
  }) {
    return AuthSession(
      userId: userId,
      username: username,
      role: role ?? this.role,
      shiftId: shiftId ?? this.shiftId,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'role': role,
      'shiftId': shiftId,
      'permissions': permissions,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: json['userId'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      shiftId: json['shiftId'] as String,
      permissions: List<String>.from(json['permissions'] as List),
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }

  @override
  String toString() =>
      'AuthSession(userId: $userId, username: $username, role: $role, expiresAt: $expiresAt)';
}
