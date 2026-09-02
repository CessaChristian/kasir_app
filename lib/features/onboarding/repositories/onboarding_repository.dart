import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../data/uuid_helper.dart';

/// Atomic operations untuk onboarding flow.
///
/// Aplikasi difokuskan ke satu bisnis (Teras Inn), jadi onboarding hanya
/// membuat akun owner. Tabel `businesses` dan `user_business_roles` sudah
/// dibuang di skema v13 — peran dibaca dari `users.role`.
class OnboardingRepository {
  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  /// Buat akun owner pertama.
  ///
  /// Throw kalau username sudah ada, atau ada DB error.
  /// Return: userId — dipakai untuk generate recovery code.
  Future<String> setupFirstOwner({
    required String username,
    required String pinHash,
    required String salt,
  }) async {
    final user = await _dbx.into(_dbx.users).insertReturning(
          UsersCompanion.insert(
            id: Value(newUuid()),
            username: username,
            pinHash: pinHash,
            salt: salt,
            role: 'owner',
          ),
        );
    return user.id;
  }

  /// Check apakah ada user sama sekali di DB.
  Future<bool> hasAnyUser() async {
    final result = await (_dbx.select(_dbx.users)
          ..where((u) => u.deletedAt.isNull() & u.isActive.equals(true))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }
}
