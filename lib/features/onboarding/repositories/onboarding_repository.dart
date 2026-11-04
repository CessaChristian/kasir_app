import '../../../data/app_database.dart';
import '../../../data/db.dart';

/// Atomic operations untuk onboarding flow.
///
/// Aplikasi difokuskan ke satu bisnis (Teras Inn), jadi onboarding hanya
/// membuat akun owner. Tabel `businesses` dan `user_business_roles` sudah
/// dibuang di skema v13 — peran dibaca dari `users.role`.
class OnboardingRepository {
  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  /// Check apakah ada user sama sekali di DB.
  Future<bool> hasAnyUser() async {
    final result = await (_dbx.select(_dbx.users)
          ..where((u) => u.isActive.equals(true))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }
}
