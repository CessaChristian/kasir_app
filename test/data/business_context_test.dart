import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Note: BusinessContext pakai global db singleton + SharedPreferences.
// Test ini test core logic via direct DB ops, plus mock SharedPreferences.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
  });

  group('BusinessContext access check pattern', () {
    test('user dengan role di business → bisa akses', () async {
      // Setup
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              name: 'Teras Inn',
              type: 'restaurant_dinein',
            ),
          );
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
              username: 'sari',
              pinHash: 'h',
              salt: 's',
              role: 'owner',
            ),
          );
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
              userId: user.id,
              businessId: business.id,
              role: 'owner',
            ),
          );

      // Test access check
      final result = await (db.select(db.userBusinessRoles)
            ..where((r) =>
                r.userId.equals(user.id) &
                r.businessId.equals(business.id) &
                r.deletedAt.isNull())
            ..limit(1))
          .get();
      expect(result, isNotEmpty);
    });

    test('user tanpa role di business → tidak bisa akses', () async {
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              name: 'Thai Tea',
              type: 'beverage_grabandgo',
            ),
          );
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
              username: 'dani',
              pinHash: 'h',
              salt: 's',
              role: 'cashier',
            ),
          );
      // Sengaja TIDAK insert user_business_roles untuk dani di Thai Tea

      final result = await (db.select(db.userBusinessRoles)
            ..where((r) =>
                r.userId.equals(user.id) &
                r.businessId.equals(business.id) &
                r.deletedAt.isNull())
            ..limit(1))
          .get();
      expect(result, isEmpty);
    });

    test('soft-deleted role → tidak bisa akses', () async {
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              name: 'Teras Inn',
              type: 'restaurant_dinein',
            ),
          );
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
              username: 'rina',
              pinHash: 'h',
              salt: 's',
              role: 'cashier',
            ),
          );
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
              userId: user.id,
              businessId: business.id,
              role: 'cashier',
              deletedAt: Value(DateTime.now()), // soft deleted
            ),
          );

      final result = await (db.select(db.userBusinessRoles)
            ..where((r) =>
                r.userId.equals(user.id) &
                r.businessId.equals(business.id) &
                r.deletedAt.isNull())
            ..limit(1))
          .get();
      expect(result, isEmpty, reason: 'Soft-deleted role tidak boleh dianggap aktif');
    });
  });

  group('Load businesses for user', () {
    test('user dengan role di 2 business → load keduanya', () async {
      final biz1 = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
                name: 'Teras Inn', type: 'restaurant_dinein'),
          );
      final biz2 = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
                name: 'Thai Tea', type: 'beverage_grabandgo'),
          );
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
                username: 'sari', pinHash: 'h', salt: 's', role: 'owner'),
          );
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
                userId: user.id, businessId: biz1.id, role: 'owner'),
          );
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
                userId: user.id, businessId: biz2.id, role: 'owner'),
          );

      final query = db.select(db.businesses).join([
        innerJoin(
          db.userBusinessRoles,
          db.userBusinessRoles.businessId.equalsExp(db.businesses.id) &
              db.userBusinessRoles.userId.equals(user.id) &
              db.userBusinessRoles.deletedAt.isNull(),
        ),
      ])
        ..where(db.businesses.deletedAt.isNull() &
            db.businesses.isActive.equals(true));

      final rows = await query.get();
      final businesses = rows.map((r) => r.readTable(db.businesses)).toList();

      expect(businesses, hasLength(2));
      final names = businesses.map((b) => b.name).toSet();
      expect(names, containsAll(['Teras Inn', 'Thai Tea']));
    });
  });
}
