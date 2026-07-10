import 'package:drift/drift.dart';
import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../data/uuid_helper.dart';

/// Atomic operations untuk onboarding flow.
///
/// Setup owner + business pertama harus atomic — kalau gagal di tengah,
/// rollback supaya tidak ada state inkonsisten (user tanpa role, atau
/// business tanpa owner).
class OnboardingRepository {
  /// Setup owner account + business pertama dalam 1 transaksi.
  ///
  /// Throw kalau username sudah ada, atau ada DB error.
  /// Return: userId + businessId yang baru dibuat (userId dibutuhkan caller
  /// untuk generate recovery code).
  Future<({String userId, String businessId})> setupFirstOwnerAndBusiness({
    required String username,
    required String pinHash,
    required String salt,
    required String businessName,
    required String businessType, // 'restaurant_dinein' | 'beverage_grabandgo'
    String? businessLogoPath,
    String? businessAddress,
    String? businessPhone,
  }) async {
    return await db.transaction(() async {
      // 1. Insert user dengan role 'owner'
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
              id: Value(newUuid()),
              username: username,
              pinHash: pinHash,
              salt: salt,
              role: 'owner',
            ),
          );

      // 2. Insert business
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              id: Value(newUuid()),
              name: businessName,
              type: businessType,
              logoPath: Value(businessLogoPath),
              address: Value(businessAddress),
              phone: Value(businessPhone),
            ),
          );

      // 3. Assign owner role di user_business_roles
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
              userId: user.id,
              businessId: business.id,
              role: 'owner',
            ),
          );

      return (userId: user.id, businessId: business.id);
    });
  }

  /// Tambah business baru untuk owner yang sudah ada.
  /// Assigns userId sebagai owner dari business baru.
  Future<String> addBusinessToOwner({
    required String userId,
    required String businessName,
    required String businessType,
    String? businessAddress,
    String? businessPhone,
  }) async {
    return await db.transaction(() async {
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              id: Value(newUuid()),
              name: businessName,
              type: businessType,
              address: Value(businessAddress),
              phone: Value(businessPhone),
            ),
          );

      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
              userId: userId,
              businessId: business.id,
              role: 'owner',
            ),
          );

      return business.id;
    });
  }

  /// Check apakah ada business sama sekali di DB.
  /// Dipakai untuk detect "first launch" state.
  Future<bool> hasAnyBusiness() async {
    final result = await (db.select(db.businesses)
          ..where((b) => b.deletedAt.isNull())
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }

  /// Check apakah ada user sama sekali di DB.
  Future<bool> hasAnyUser() async {
    final result = await (db.select(db.users)
          ..where((u) => u.deletedAt.isNull() & u.isActive.equals(true))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }
}
