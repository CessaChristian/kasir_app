import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci perilaku ShiftRepository — terutama perhitungan pendapatan shift.
///
/// Sebelum dipindah ke repository, query pendapatan shift ditulis langsung di
/// dashboard_page TANPA filter `deletedAt`, sehingga transaksi yang sudah
/// dihapus kasir tetap terhitung sebagai pendapatan pada dialog tutup shift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ShiftRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ShiftRepository(db);

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
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Nasi Goreng',
          price: 15000,
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'kasir-1',
      username: 'sari',
      role: 'owner', // owner = punya semua permission
      shiftId: 'shift-1',
      permissions: const [],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<String> jual({required String invoiceNo, int qty = 1}) async {
    final id = 'trx-$invoiceNo';
    await db.createSale(
      transactionId: id,
      paymentMethod: 'qris',
      orderType: 'dine_in',
      shiftId: 'shift-1',
      cashierUserId: 'kasir-1',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Nasi Goreng',
          qty: qty,
          priceAtSale: 15000,
          trackStock: false,
        ),
      ],
    );
    return id;
  }

  test('getById mengembalikan shift yang diminta', () async {
    final s = await repo.getById('shift-1');
    expect(s, isNotNull);
    expect(s!.userId, 'kasir-1');
    expect(s.endAt, isNull, reason: 'shift masih berjalan');

    expect(await repo.getById('tidak-ada'), isNull);
  });

  test('getShiftRevenue menjumlahkan transaksi shift', () async {
    await jual(invoiceNo: 'A1');
    await jual(invoiceNo: 'A2', qty: 2);

    expect(await repo.getShiftRevenue('shift-1'), 45000);
  });

  test('transaksi yang dihapus TIDAK ikut dihitung', () async {
    await jual(invoiceNo: 'A1');
    final dibuang = await jual(invoiceNo: 'A2');

    expect(await repo.getShiftRevenue('shift-1'), 30000,
        reason: 'prasyarat: dua transaksi terhitung');

    await db.softDeleteTransaction(dibuang);

    // Inilah bug yang diperbaiki: tanpa filter deletedAt, hasilnya tetap 30000
    // dan kasir melihat pendapatan shift lebih besar dari kenyataan.
    expect(await repo.getShiftRevenue('shift-1'), 15000,
        reason: 'transaksi terhapus tidak boleh menambah pendapatan shift');

    expect(await repo.getTransactionsForShift('shift-1'), hasLength(1));
  });

  test('getShiftsByUser hanya membawa shift business aktif', () async {
    final shifts = await repo.getShiftsByUser('kasir-1');
    expect(shifts, hasLength(1));
    expect(shifts.single.id, 'shift-1');

    expect(await repo.getShiftsByUser('entah-siapa'), isEmpty);
  });
}
