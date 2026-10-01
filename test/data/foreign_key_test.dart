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

  test('1. PRAGMA foreign_keys aktif di koneksi aplikasi', () async {
    final rows = await db.customSelect('PRAGMA foreign_keys').get();
    expect(rows.first.data.values.first, 1,
        reason: 'foreign key harus ditegakkan (1 = ON)');
  });

  test('2. insert dengan induk yang tidak ada DITOLAK', () async {
    await expectLater(
      db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: const Value('shift-hantu'),
            userId: 'user-yang-tidak-ada',
          )),
      throwsA(anything),
      reason: 'user_id ngawur harus ditolak database',
    );

    final all = await db.select(db.shifts).get();
    expect(all, isEmpty, reason: 'tidak boleh ada baris yatim yang lolos');
  });

  test('3. deleteCategory tetap berhasil walau kategori masih dipakai produk',
      () async {
    await loginAsOwner();

    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const Value('cat-1'),
          name: 'Makanan',
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
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
    // Sebelumnya test ini menunjuk 'prod-1' yang tidak pernah dibuat, dan
    // database menerimanya tanpa protes.
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Nasi Goreng',
          price: 15000,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          total: 15000,
          paymentMethod: 'cash',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-1'),
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

  test('5. produk yang pernah terjual BOLEH dibuang, struknya tetap utuh',
      () async {
    // ── ATURAN INI PERNAH SEBALIKNYA ──
    //
    // Sejak v14 sampai v23, membuang produk yang pernah laku DITOLAK, dengan
    // alasan "item struknya jadi yatim dan riwayat penjualan rusak". Alasan
    // itu tidak pernah benar: item struk menyalin nama dan harganya sendiri,
    // dan tidak ada laporan yang mencari produk lewat `product_id`.
    //
    // Yang justru ditimbulkan larangan itu: produk tidak pernah bisa dibuang
    // dari server, dan HP baru yang menarik riwayat lama akan menolak item
    // yang produknya sudah tiada — riwayatnya bolong diam-diam. Dilepas di v24.
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Nasi Goreng',
          price: 15000,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          total: 15000,
          paymentMethod: 'cash',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-1'),
          transactionId: 'trx-1',
          productId: 'prod-1',
          productName: const Value('Nasi Goreng'),
          qty: 1,
          priceAtSale: 15000,
          subtotal: 15000,
        ));

    await (db.delete(db.products)..where((p) => p.id.equals('prod-1'))).go();

    expect(await db.select(db.products).get(), isEmpty);

    final item = await db.select(db.transactionItems).getSingle();
    expect(item.productName, 'Nasi Goreng',
        reason: 'struk lama harus tetap menyebut nama produknya walau '
            'produknya sudah dibuang — itulah gunanya salinan nama');
    expect(item.priceAtSale, 15000);
  });

  test('6. soft delete produk terjual TETAP boleh — FK tidak menghalangi',
      () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Nasi Goreng',
          price: 15000,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          total: 15000,
          paymentMethod: 'cash',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-1'),
          transactionId: 'trx-1',
          productId: 'prod-1',
          productName: const Value('Nasi Goreng'),
          qty: 1,
          priceAtSale: 15000,
          subtotal: 15000,
        ));

    await loginAsOwner();
    await db.deleteProduct('prod-1');

    final p = await (db.select(db.products)
          ..where((t) => t.id.equals('prod-1')))
        .getSingle();
    expect(p.deletedAt, isNotNull, reason: 'baris ditandai terhapus');

    final item = await (db.select(db.transactionItems)
          ..where((i) => i.id.equals('item-1')))
        .getSingle();
    expect(item.productName, 'Nasi Goreng',
        reason: 'struk lama tetap menampilkan nama produk saat transaksi');
  });

  test('7. transaksi dengan shift_id hantu DITOLAK', () async {
    await expectLater(
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: const Value('trx-hantu'),
            total: 1000,
            paymentMethod: 'cash',
            shiftId: const Value('shift-yang-tidak-ada'),
          )),
      throwsA(anything),
      reason: 'shift_id ngawur harus ditolak database',
    );
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('8. transaksi dengan cashier_user_id hantu DITOLAK', () async {
    await expectLater(
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: const Value('trx-hantu'),
            total: 1000,
            paymentMethod: 'cash',
            cashierUserId: const Value('user-yang-tidak-ada'),
          )),
      throwsA(anything),
      reason: 'cashier_user_id ngawur harus ditolak database',
    );
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('9. item struk yang produknya sudah tiada DITERIMA', () async {
    // Inilah syarat HP yang baru dipasang bisa menarik riwayat lama. Begitu
    // produknya dibuang dari server, item struk lamanya tetap ikut tertarik
    // — dan kalau ditolak di sini, riwayat HP itu bolong tanpa pesan apa pun.
    //
    // Validitas `product_id` saat BERJUALAN tetap dijaga aplikasi lewat
    // `_validasiProdukMasihAda` di `createSale`; yang dilepas cuma rantai
    // di tingkat database.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          total: 1000,
          paymentMethod: 'cash',
        ));

    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Value('item-lama'),
          transactionId: 'trx-1',
          productId: 'produk-yang-sudah-dibuang',
          productName: const Value('Es Kopi Susu'),
          qty: 1,
          priceAtSale: 1000,
          subtotal: 1000,
        ));

    final item = await db.select(db.transactionItems).getSingle();
    expect(item.productName, 'Es Kopi Susu');
  });
}
