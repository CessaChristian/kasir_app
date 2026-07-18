import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../data/uuid_helper.dart';

/// Dua business client di-HARDCODE dari kode (spec 2026-07-18 REVISI 2, D3).
/// Tidak ada UI tambah business — kalau client menambah bisnis baru atau
/// mengganti nama Thai Tea, ubah konstanta ini.
const kSeedBusinesses = [
  (name: 'Teras Inn', type: 'restaurant_dinein'),
  (name: 'Thai Tea', type: 'beverage_grabandgo'),
];

/// Atomic operations untuk onboarding flow.
///
/// Setup owner + seed business harus atomic — kalau gagal di tengah,
/// rollback supaya tidak ada state inkonsisten (user tanpa role, atau
/// business tanpa owner).
class OnboardingRepository {
  /// Override DB untuk unit test. JANGAN dipakai di production code.
  static AppDatabase? dbOverride;
  AppDatabase get _dbx => dbOverride ?? db;

  /// Setup owner account + seed DUA business hardcode dalam 1 transaksi.
  ///
  /// Throw kalau username sudah ada, atau ada DB error.
  /// Return: userId (untuk generate recovery code) + terasInnId (business
  /// dine-in — business aktif pertama setelah onboarding).
  Future<({String userId, String terasInnId})> setupFirstOwner({
    required String username,
    required String pinHash,
    required String salt,
  }) async {
    return await _dbx.transaction(() async {
      // 1. Insert user dengan role 'owner'
      final user = await _dbx.into(_dbx.users).insertReturning(
            UsersCompanion.insert(
              id: Value(newUuid()),
              username: username,
              pinHash: pinHash,
              salt: salt,
              role: 'owner',
            ),
          );

      // 2. Seed kedua business + role owner untuk masing-masing
      String? terasInnId;
      for (final seed in kSeedBusinesses) {
        final business = await _dbx.into(_dbx.businesses).insertReturning(
              BusinessesCompanion.insert(
                id: Value(newUuid()),
                name: seed.name,
                type: seed.type,
              ),
            );
        if (seed.type == 'restaurant_dinein') terasInnId = business.id;

        await _dbx.into(_dbx.userBusinessRoles).insert(
              UserBusinessRolesCompanion.insert(
                userId: user.id,
                businessId: business.id,
                role: 'owner',
              ),
            );
      }

      return (userId: user.id, terasInnId: terasInnId!);
    });
  }

  /// Check apakah ada business sama sekali di DB.
  /// Dipakai untuk detect "first launch" state.
  Future<bool> hasAnyBusiness() async {
    final result = await (_dbx.select(_dbx.businesses)
          ..where((b) => b.deletedAt.isNull())
          ..limit(1))
        .get();
    return result.isNotEmpty;
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
