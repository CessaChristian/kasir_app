import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menguji bahwa penegakan foreign key benar-benar AKTIF.
///
/// SQLite mematikan `PRAGMA foreign_keys` secara default, sehingga semua
/// `REFERENCES` di skema hanya jadi dokumentasi. Test ini mengunci perilaku
/// setelah pragma dinyalakan di `AppDatabase.migration.beforeOpen`, sekaligus
/// membuktikan bahwa alur hapus yang sudah ada TIDAK ikut rusak.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Query pertama memicu beforeOpen (tempat pragma dipasang).
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  /// Sebagian method DB dijaga permission. Owner otomatis punya semua izin.
  Future<void> loginAsOwner() async {
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'owner-1',
      username: 'owner',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ));
  }

  Future<String> makeBusiness([String id = 'biz-a']) async {
    await db.into(db.businesses).insert(BusinessesCompanion.insert(
          id: Value(id),
          name: 'Teras Inn',
          type: 'restaurant_dinein',
        ));
    return id;
  }

  test('1. PRAGMA foreign_keys aktif di koneksi aplikasi', () async {
    final rows = await db.customSelect('PRAGMA foreign_keys').get();
    expect(rows.first.data.values.first, 1,
        reason: 'foreign key harus ditegakkan (1 = ON)');
  });

  test('2. insert dengan induk yang tidak ada DITOLAK', () async {
    await expectLater(
      db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value('p-hantu'),
            businessId: 'business-yang-tidak-ada',
            name: 'Produk Hantu',
            price: 1000,
          )),
      throwsA(anything),
      reason: 'business_id ngawur harus ditolak database',
    );

    final all = await db.select(db.products).get();
    expect(all, isEmpty, reason: 'tidak boleh ada baris yatim yang lolos');
  });

  test('3. deleteCategory tetap berhasil walau kategori masih dipakai produk',
      () async {
    final bizId = await makeBusiness();
    AppDatabase.activeBusinessIdProvider = () => bizId;
    addTearDown(() => AppDatabase.activeBusinessIdProvider = null);
    await loginAsOwner();

    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const Value('cat-1'),
          businessId: bizId,
          name: 'Makanan',
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          businessId: bizId,
          name: 'Nasi Goreng',
          price: 15000,
          categoryId: const Value('cat-1'),
        ));

    // deleteCategory melepas produk dulu (category_id = NULL) baru menandai
    // kategorinya terhapus, semuanya dalam satu transaction — jadi FK tidak
    // terlanggar.
    await db.deleteCategory('cat-1');

    // Soft delete: barisnya SENGAJA tetap ada supaya penghapusannya bisa
    // disebarkan ke device lain saat sync.
    final row = await (db.select(db.categories)
          ..where((c) => c.id.equals('cat-1')))
        .getSingle();
    expect(row.deletedAt, isNotNull, reason: 'kategori ditandai terhapus');
    expect(row.syncStatus, 'pending', reason: 'perlu dikirim ke server');

    // Dari sisi aplikasi kategori itu harus hilang.
    final terlihat = await db.watchCategories().first;
    expect(terlihat, isEmpty, reason: 'kategori tidak muncul lagi di UI');

    final product = await (db.select(db.products)
          ..where((p) => p.id.equals('prod-1')))
        .getSingle();
    expect(product.categoryId, isNull,
        reason: 'produk tetap ada, hanya jadi tanpa kategori');
  });

  test('4. ON DELETE CASCADE benar-benar jalan pada transaction_items',
      () async {
    final bizId = await makeBusiness();

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          businessId: bizId,
          total: 15000,
          paymentMethod: 'cash',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-1'),
          businessId: bizId,
          transactionId: 'trx-1',
          productId: 'prod-1',
          qty: 1,
          priceAtSale: 15000,
          subtotal: 15000,
        ));

    await (db.delete(db.transactions)..where((t) => t.id.equals('trx-1'))).go();

    final items = await db.select(db.transactionItems).get();
    expect(items, isEmpty,
        reason: 'item ikut terhapus otomatis lewat ON DELETE CASCADE');
  });

  test('5. hapus produk yang sudah pernah terjual tetap boleh', () async {
    final bizId = await makeBusiness();
    AppDatabase.activeBusinessIdProvider = () => bizId;
    addTearDown(() => AppDatabase.activeBusinessIdProvider = null);

    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          businessId: bizId,
          name: 'Nasi Goreng',
          price: 15000,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          businessId: bizId,
          total: 15000,
          paymentMethod: 'cash',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-1'),
          businessId: bizId,
          transactionId: 'trx-1',
          productId: 'prod-1',
          productName: const Value('Nasi Goreng'),
          qty: 1,
          priceAtSale: 15000,
          subtotal: 15000,
        ));

    // transaction_items.product_id SENGAJA tidak diberi FK supaya struk lama
    // tetap utuh walau produknya dihapus.
    await (db.delete(db.products)..where((p) => p.id.equals('prod-1'))).go();

    final item = await (db.select(db.transactionItems)
          ..where((i) => i.id.equals('item-1')))
        .getSingle();
    expect(item.productName, 'Nasi Goreng',
        reason: 'struk lama tetap menampilkan nama produk saat transaksi');
  });
}
