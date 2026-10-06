import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_app/features/report/repositories/laporan_repository.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';

/// Mengunci perilaku soft delete.
///
/// Latar belakang — produk, kategori, dan pengeluaran dulu dihapus secara
/// FISIK. Baris yang lenyap tidak bisa diberitahukan ke device lain saat sync:
/// server hanya melihat ketiadaan, dan ketiadaan tidak bisa dikirim. Akibatnya
/// server mengirim balik baris yang sudah dihapus dan barisnya "hidup lagi"
/// (zombie record).
///
/// Menyimpan baris berarti setiap query baca WAJIB memfilter `deletedAt`.
/// Dua jalur di bawah pernah terlewat dan gagal secara DIAM-DIAM, jadi
/// keduanya dikunci di sini.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'sari',
          pinHash: 'hash',
          salt: 'salt',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'kasir-1',
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'kasir-1',
      username: 'sari',
      role: 'cashier',
      shiftId: 'shift-1',
      permissions: const ['create_transaction', 'manage_products'],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> makeProduct() async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Nasi Goreng',
          price: 15000,
        ));
  }

  test('deleteProduct menandai terhapus, barisnya tetap ada', () async {
    await makeProduct();

    await db.deleteProduct('prod-1');

    final row = await (db.select(db.products)
          ..where((p) => p.id.equals('prod-1')))
        .getSingle();
    expect(row.deletedAt, isNotNull, reason: 'ditandai terhapus, bukan dibuang');
    expect(row.syncStatus, 'pending', reason: 'perlu dikirim ke server');

    expect(await db.watchProducts().first, isEmpty,
        reason: 'produk tidak muncul lagi di UI');
  });

  test('produk yang sudah dihapus TIDAK bisa terjual', () async {
    await makeProduct();
    await db.deleteProduct('prod-1');

    // Sebelum perbaikan, validasi produk tidak memfilter deletedAt
    // sehingga produk yang sudah dihapus masih ditemukan dan tetap laku.
    await expectLater(
      db.createSale(
        transactionId: 'trx-1',
        paymentMethod: 'qris',
        orderType: 'dine_in',
        lines: [
          SaleLine(
            productId: 'prod-1',
            productName: 'Nasi Goreng',
            qty: 1,
            priceAtSale: 15000,
          ),
        ],
        kodePerangkat: 'TEST',
      ),
      throwsA(isA<StateError>()),
      reason: 'checkout harus menolak produk yang sudah dihapus',
    );

    expect(await db.select(db.transactions).get(), isEmpty,
        reason: 'tidak boleh ada transaksi yang tercatat',
    );
  });

  test('pengeluaran batal ditandai dan tidak ikut di daftar shift bawaan',
      () async {
    await db.addExpense(
      shiftId: 'shift-1',
      userId: 'kasir-1',
      description: 'Beli gas',
      amount: 25000,
    );
    final expense = await db.select(db.expenses).getSingle();

    await db.batalkanPengeluaran(expense.id,
        olehUserId: 'kasir-1', alasan: 'Salah input');

    final row = await db.select(db.expenses).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.syncStatus, 'pending');

    expect(await db.watchExpensesByShift('shift-1').first, isEmpty,
        reason: 'pengeluaran tidak muncul lagi di daftar shift');
  });

  test('pengeluaran yang dibatalkan tidak ikut terhitung di Laporan',
      () async {
    await makeProduct();

    // Satu penjualan supaya kasir muncul di laporan.
    await db.createSale(
      transactionId: 'trx-1',
      paymentMethod: 'qris',
      orderType: 'dine_in',
      cashierUserId: 'kasir-1',
      shiftId: 'shift-1',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Nasi Goreng',
          qty: 1,
          priceAtSale: 15000,
        ),
      ],
      kodePerangkat: 'TEST',
    );

    await db.addExpense(
      shiftId: 'shift-1',
      userId: 'kasir-1',
      description: 'Beli gas',
      amount: 25000,
    );
    final expense = await db.select(db.expenses).getSingle();

    final laporan = LaporanRepository(db);
    final hariIni = Periode.hari(DateTime.now());

    final sebelum = await laporan.muat(hariIni);
    expect(sebelum.pengeluaran, 25000,
        reason: 'prasyarat: pengeluaran memang terhitung dulu');

    await db.batalkanPengeluaran(expense.id,
        olehUserId: 'kasir-1', alasan: 'Salah input');

    // Laporan lama pernah tidak memfilter deletedAt, sehingga pengeluaran
    // yang sudah dibatalkan tetap mengurangi laba — salah hitung tanpa error
    // apa pun.
    final sesudah = await laporan.muat(hariIni);
    expect(sesudah.pengeluaran, 0,
        reason: 'pengeluaran terhapus tidak boleh ikut dihitung');
    expect(sesudah.pengeluaranBatal.single.description, 'Beli gas',
        reason: 'tetap tercatat di bagian Pengeluaran Dibatalkan');
    expect(sesudah.labaKotor, 15000);
  });
}
