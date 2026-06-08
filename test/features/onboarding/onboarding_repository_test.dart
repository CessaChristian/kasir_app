import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  // Note: OnboardingRepository pakai global db singleton, jadi tidak bisa
  // di-test langsung tanpa refactor. Test ini test pattern equivalent
  // dengan in-memory DB untuk verifikasi schema + atomic insert.
  group('Onboarding flow (manual atomic insert via in-memory DB)', () {
    test('atomic insert: user + business + role berhasil bersama', () async {
      await db.transaction(() async {
        final user = await db.into(db.users).insertReturning(
              UsersCompanion.insert(
                username: 'sari',
                pinHash: 'hash',
                salt: 'salt',
                role: 'owner',
              ),
            );
        final business = await db.into(db.businesses).insertReturning(
              BusinessesCompanion.insert(
                name: 'Teras Inn',
                type: 'restaurant_dinein',
              ),
            );
        await db.into(db.userBusinessRoles).insert(
              UserBusinessRolesCompanion.insert(
                userId: user.id,
                businessId: business.id,
                role: 'owner',
              ),
            );
      });

      // Verify semua ter-insert
      final users = await db.select(db.users).get();
      final businesses = await db.select(db.businesses).get();
      final roles = await db.select(db.userBusinessRoles).get();

      expect(users, hasLength(1));
      expect(businesses, hasLength(1));
      expect(roles, hasLength(1));
      expect(roles.first.userId, equals(users.first.id));
      expect(roles.first.businessId, equals(businesses.first.id));
      expect(roles.first.role, equals('owner'));
    });

    test('hasAnyBusiness equivalent: detect first launch', () async {
      // Initially kosong
      final initial = await (db.select(db.businesses)
            ..where((b) => b.deletedAt.isNull())
            ..limit(1))
          .get();
      expect(initial, isEmpty, reason: 'First launch — no business');

      // Insert 1 business
      await db.into(db.businesses).insert(
            BusinessesCompanion.insert(
              name: 'Teras Inn',
              type: 'restaurant_dinein',
            ),
          );

      // Now should detect
      final after = await (db.select(db.businesses)
            ..where((b) => b.deletedAt.isNull())
            ..limit(1))
          .get();
      expect(after, hasLength(1));
    });
  });
}
