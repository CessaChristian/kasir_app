import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Buang sampah di HP: baris yang sudah dihapus, sudah sampai di server, dan
/// sudah lewat 30 hari dibuang permanen dari database HP.
///
/// Yang paling penting dijaga: baris yang kabar hapusnya BELUM terkirim
/// tidak boleh ikut terbuang. Kalau terbuang, kabar itu hilang dan barisnya
/// tetap hidup di HP lain selamanya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final sekarang = DateTime(2026, 11, 15, 12);
  final lama = sekarang.subtract(const Duration(days: 31));
  final baru = sekarang.subtract(const Duration(days: 10));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('u-1'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('s-1'),
          userId: 'u-1',
        ));
  });

  tearDown(() => db.close());

  Future<void> trx(String id, {DateTime? dihapus, String status = 'synced'}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: Value(id),
          shiftId: const Value('s-1'),
          cashierUserId: const Value('u-1'),
          total: 10000,
          paymentMethod: 'cash',
          deletedAt: Value(dihapus),
          syncStatus: Value(status),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: Value('$id-item'),
          transactionId: id,
          productId: 'p-x',
          productName: const Value('Kopi'),
          qty: 1,
          priceAtSale: 10000,
          subtotal: 10000,
          syncStatus: const Value('synced'),
        ));
  }

  Future<List<String>> idTransaksi() async =>
      (await db.select(db.transactions).get()).map((t) => t.id).toList();

  Future<List<String>> idItem() async =>
      (await db.select(db.transactionItems).get()).map((i) => i.id).toList();

  test('transaksi terhapus, terkirim, lewat 30 hari: dibuang BESERTA itemnya',
      () async {
    await trx('aktif');
    await trx('sampah', dihapus: lama);

    final hasil = await db.buangSampahLokal(sekarang: sekarang);

    expect(hasil['transaksi'], 1);
    expect(await idTransaksi(), ['aktif']);
    expect(await idItem(), ['aktif-item'],
        reason: 'item milik transaksi yang dibuang tidak boleh tertinggal');
  });

  test('kabar hapus yang BELUM terkirim tidak dibuang', () async {
    await trx('belum-terkirim', dihapus: lama, status: 'pending');

    await db.buangSampahLokal(sekarang: sekarang);

    expect(await idTransaksi(), ['belum-terkirim'],
        reason: 'kalau dibuang, server tidak pernah tahu barisnya dihapus');
  });

  test('yang dihapus kurang dari 30 hari lalu belum dibuang', () async {
    await trx('masih-baru', dihapus: baru);

    await db.buangSampahLokal(sekarang: sekarang);

    expect(await idTransaksi(), ['masih-baru']);
  });

  test('pengeluaran dan produk ikut dibersihkan', () async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: const Value('e-sampah'),
          shiftId: 's-1',
          userId: 'u-1',
          description: 'Es batu',
          amount: 5000,
          deletedAt: Value(lama),
          syncStatus: const Value('synced'),
        ));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: const Value('e-aktif'),
          shiftId: 's-1',
          userId: 'u-1',
          description: 'Gula',
          amount: 7000,
          syncStatus: const Value('synced'),
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('p-sampah'),
          name: 'Teh lama',
          price: 4000,
          deletedAt: Value(lama),
          syncStatus: const Value('synced'),
        ));

    final hasil = await db.buangSampahLokal(sekarang: sekarang);

    expect(hasil['pengeluaran'], 1);
    expect(hasil['produk'], 1);
    expect((await db.select(db.expenses).get()).map((e) => e.id), ['e-aktif']);
    expect(await db.select(db.products).get(), isEmpty);
  });

  test('kategori yang masih ditunjuk produk dilewati, yang lain dibuang',
      () async {
    for (final id in ['k-dipakai', 'k-kosong']) {
      await db.into(db.categories).insert(CategoriesCompanion.insert(
            id: Value(id),
            name: id,
            deletedAt: Value(lama),
            syncStatus: const Value('synced'),
          ));
    }
    // HP lain yang offline memasukkan produk ke kategori yang sudah dihapus.
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('p-1'),
          name: 'Es Teh',
          price: 5000,
          categoryId: const Value('k-dipakai'),
          syncStatus: const Value('synced'),
        ));

    final hasil = await db.buangSampahLokal(sekarang: sekarang);

    expect(hasil['kategori'], 1);
    expect((await db.select(db.categories).get()).map((c) => c.id),
        ['k-dipakai']);
  });
}
