import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shift yang sudah ditutup — biasanya dari HP lain yang memegang shift yang
/// sama — tidak boleh menerima penjualan atau pengeluaran lagi. Kalau lolos,
/// kas akhir shift yang sudah diserahkan ikut berubah.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalesRepository jual;
  late ExpenseRepository keluar;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    jual = SalesRepository(db);
    keluar = ExpenseRepository(db);
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('k-1'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value('teh'), name: 'Teh', price: 8000));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: 's-1',
      permissions: const ['create_transaction'],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<void> tutupShiftDariHpLain() =>
      (db.update(db.shifts)..where((s) => s.id.equals('s-1')))
          .write(ShiftsCompanion(endAt: Value(DateTime.now())));

  Future<String> jualTeh() => jual.createSale(
        transactionId: 'tx-1',
        lines: [
          SaleLine(productId: 'teh', productName: 'Teh', qty: 1, priceAtSale: 8000),
        ],
        paymentMethod: 'qris',
        orderType: 'dine_in',
        cashierUserId: 'k-1',
        shiftId: 's-1',
      );

  Future<void> catatEs() => keluar.addExpense(
        shiftId: 's-1',
        userId: 'k-1',
        description: 'Es batu',
        amount: 5000,
      );

  test('shift masih berjalan: penjualan & pengeluaran tercatat', () async {
    await jualTeh();
    await catatEs();
    expect(await db.select(db.transactions).get(), hasLength(1));
    expect(await db.select(db.expenses).get(), hasLength(1));
  });

  test('shift sudah ditutup: penjualan ditolak, tidak ada baris tertulis',
      () async {
    await tutupShiftDariHpLain();
    await expectLater(jualTeh(), throwsA(isA<ShiftSudahDitutup>()));
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.transactionItems).get(), isEmpty);
  });

  test('shift sudah ditutup: pengeluaran ditolak', () async {
    await tutupShiftDariHpLain();
    await expectLater(catatEs(), throwsA(isA<ShiftSudahDitutup>()));
    expect(await db.select(db.expenses).get(), isEmpty);
  });

  test('pesan penolakannya bisa dibaca kasir', () {
    expect(
      ShiftSudahDitutup().message,
      'Shift ini sudah ditutup di perangkat lain. '
      'Buka shift baru untuk melanjutkan.',
    );
  });

  test('owner mencatat pengeluaran tanpa shift tetap boleh', () async {
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ));
    await keluar.addExpense(
      shiftId: null,
      userId: 'k-1',
      description: 'Gas',
      amount: 25000,
    );
    expect(await db.select(db.expenses).get(), hasLength(1));
  });

  test('audit 6 Nov nomor 59: produk yang dihapus di keranjang ditolak, '
      'yang disebut baris pertama yang hilang', () async {
    for (final (id, nama) in [('kopi', 'Kopi'), ('roti', 'Roti')]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: nama,
            price: 5000,
            deletedAt: Value(DateTime(2026, 11, 9)),
          ));
    }
    SaleLine baris(String id, String nama) =>
        SaleLine(productId: id, productName: nama, qty: 1, priceAtSale: 5000);
    await expectLater(
      jual.createSale(
        transactionId: 'tx-2',
        lines: [baris('teh', 'Teh'), baris('kopi', 'Kopi'), baris('roti', 'Roti')],
        paymentMethod: 'qris',
        orderType: 'dine_in',
        cashierUserId: 'k-1',
        shiftId: 's-1',
      ),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'pesan', contains('"Kopi" sudah tidak tersedia'))),
    );
    expect(await db.select(db.transactions).get(), isEmpty);
    // Keranjang yang semua produknya masih ada tetap lolos.
    await jualTeh();
  });
}

