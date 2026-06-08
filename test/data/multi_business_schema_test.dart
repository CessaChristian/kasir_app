import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  group('Schema v10 — multi-business', () {
    test('Businesses table exists dan bisa insert', () async {
      final id = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              name: 'Teras Inn',
              type: 'restaurant_dinein',
            ),
          );

      expect(id.id, isNotEmpty);
      expect(id.name, equals('Teras Inn'));
      expect(id.type, equals('restaurant_dinein'));
      expect(id.isActive, isTrue);
      expect(id.syncStatus, equals('pending'));
      expect(id.deletedAt, isNull);
    });

    test('UserBusinessRoles many-to-many works', () async {
      // Insert business
      final business = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
              name: 'Teras Inn',
              type: 'restaurant_dinein',
            ),
          );

      // Insert user (existing schema)
      final user = await db.into(db.users).insertReturning(
            UsersCompanion.insert(
              username: 'sari',
              pinHash: 'hash',
              salt: 'salt',
              role: 'owner',
            ),
          );

      // Assign owner role to user for this business
      await db.into(db.userBusinessRoles).insert(
            UserBusinessRolesCompanion.insert(
              userId: user.id,
              businessId: business.id,
              role: 'owner',
            ),
          );

      // Verify
      final roles = await (db.select(db.userBusinessRoles)
            ..where((r) => r.userId.equals(user.id)))
          .get();

      expect(roles, hasLength(1));
      expect(roles.first.businessId, equals(business.id));
      expect(roles.first.role, equals('owner'));
    });

    test('Products scoped by business_id', () async {
      final biz1 = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
                name: 'Teras Inn', type: 'restaurant_dinein'),
          );
      final biz2 = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
                name: 'Thai Tea', type: 'beverage_grabandgo'),
          );

      // Insert kategori untuk biz1
      final cat1 = await db.into(db.categories).insertReturning(
            CategoriesCompanion.insert(
              businessId: biz1.id,
              name: 'Makanan',
            ),
          );

      // Insert product di biz1
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              businessId: biz1.id,
              name: 'Nasi Goreng',
              price: 25000,
              categoryId: Value(cat1.id),
            ),
          );

      // Insert product di biz2
      final cat2 = await db.into(db.categories).insertReturning(
            CategoriesCompanion.insert(
              businessId: biz2.id,
              name: 'Minuman Original',
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              businessId: biz2.id,
              name: 'Thai Tea Original',
              price: 15000,
              categoryId: Value(cat2.id),
            ),
          );

      // Query products dari biz1 — should return 1
      final biz1Products = await (db.select(db.products)
            ..where((p) => p.businessId.equals(biz1.id)))
          .get();
      expect(biz1Products, hasLength(1));
      expect(biz1Products.first.name, equals('Nasi Goreng'));

      // Query products dari biz2 — should return 1
      final biz2Products = await (db.select(db.products)
            ..where((p) => p.businessId.equals(biz2.id)))
          .get();
      expect(biz2Products, hasLength(1));
      expect(biz2Products.first.name, equals('Thai Tea Original'));
    });

    test('Soft delete pattern works (deleted_at)', () async {
      final biz = await db.into(db.businesses).insertReturning(
            BusinessesCompanion.insert(
                name: 'Teras Inn', type: 'restaurant_dinein'),
          );
      final cat = await db.into(db.categories).insertReturning(
            CategoriesCompanion.insert(
                businessId: biz.id, name: 'Makanan'),
          );
      final prod = await db.into(db.products).insertReturning(
            ProductsCompanion.insert(
              businessId: biz.id,
              name: 'Nasi Goreng',
              price: 25000,
              categoryId: Value(cat.id),
            ),
          );

      // Soft delete
      await (db.update(db.products)..where((p) => p.id.equals(prod.id))).write(
        ProductsCompanion(
          deletedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );

      // Query active only — should return 0
      final activeProducts = await (db.select(db.products)
            ..where((p) =>
                p.businessId.equals(biz.id) & p.deletedAt.isNull()))
          .get();
      expect(activeProducts, isEmpty);

      // Query all (including deleted) — should return 1
      final allProducts = await (db.select(db.products)
            ..where((p) => p.businessId.equals(biz.id)))
          .get();
      expect(allProducts, hasLength(1));
      expect(allProducts.first.deletedAt, isNotNull);
    });

    test('Permission baru ter-seed', () async {
      final perms = await db.select(db.permissions).get();
      final codes = perms.map((p) => p.code).toSet();

      // Verify permission baru ada
      expect(codes, contains('edit_own_expense'));
      expect(codes, contains('edit_any_expense'));
      expect(codes, contains('delete_own_transaction'));
      expect(codes, contains('delete_any_transaction'));
      expect(codes, contains('view_shift_reports'));
      expect(codes, contains('manage_business'));
      expect(codes, contains('switch_business'));

      // Verify permission existing tetap
      expect(codes, contains('create_transaction'));
      expect(codes, contains('manage_products'));
    });
  });
}
