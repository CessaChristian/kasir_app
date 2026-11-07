import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/open_bill/models/isi_bill.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 6 Nov nomor 25: menyembunyikan bill "sudah dibayar HP lain" memakai
/// `deleted_at`. Bill yang masih menunggu dikirim membawa tanda itu ke server
/// dan terhapus di semua HP, walau sebenarnya masih terbuka.
void main() {
  late AppDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value('k-1'), username: 'sari', pinHash: 'h', salt: 's',
        role: 'cashier'));
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
  });
  tearDown(() => db.close());

  Future<OpenBill> bill(String status) async {
    await db.into(db.openBills).insert(OpenBillsCompanion.insert(
          id: Value('b-$status'),
          name: 'Meja $status',
          shiftId: 's-1',
          userId: 'k-1',
          items: '[]',
          syncStatus: Value(status),
        ));
    await OpenBillRepository(db).tandaiTertutup('b-$status');
    return (db.select(db.openBills)..where((b) => b.id.equals('b-$status')))
        .getSingle();
  }

  test('bill yang sudah terkirim langsung disembunyikan', () async {
    expect((await bill('synced')).deletedAt, isNotNull);
  });

  test('bill yang belum terkirim TIDAK disembunyikan lewat deleted_at',
      () async {
    final b = await bill('pending');
    expect(b.deletedAt, isNull, reason: 'akan ikut terkirim sebagai hapus');
  });

  test('audit nomor 26: gabungan yang mengosongkan bill tidak disimpan',
      () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value('latte'), name: 'Latte', price: 18000));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value('teh'), name: 'Teh', price: 5000));
    SessionManager.dbOverride = db;
    addTearDown(() async {
      await SessionManager.instance.clearSession();
      SessionManager.dbOverride = null;
    });
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: 's-1',
      permissions: const ['create_transaction'],
    ));
    final repo = OpenBillRepository(db);
    final awal = kodekanBarisBill([
      (idProduk: 'latte', jumlah: 1, catatan: null),
      (idProduk: 'teh', jumlah: 1, catatan: null),
    ]);
    final id = await repo.simpan(nama: 'Meja 1', baris: [
      SaleLine(productId: 'latte', productName: 'Latte', qty: 1, priceAtSale: 1),
      SaleLine(productId: 'teh', productName: 'Teh', qty: 1, priceAtSale: 1),
    ]);
    // HP ini menghapus Latte, HP lain (server) menghapus Teh.
    await expectLater(
      repo.simpan(
        id: id,
        nama: 'Meja 1',
        baris: [SaleLine(productId: 'teh', productName: 'Teh', qty: 1, priceAtSale: 1)],
        isiAwal: awal,
        isiServer: kodekanBarisBill([(idProduk: 'latte', jumlah: 1, catatan: null)]),
      ),
      throwsA(isA<BillJadiKosong>()),
    );
    final b = await db.select(db.openBills).getSingle();
    expect(b.items, isNot('[]'));
  });
}
