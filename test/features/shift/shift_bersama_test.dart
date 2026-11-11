import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 6 Nov nomor 23, 29 & 30: satu aturan "shift ini masih jalan atau
/// pindah ke mana" untuk bayar, simpan bill, dan tutup shift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('k-1'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('teh'),
          name: 'Teh',
          price: 5000,
        ));
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<void> masukDenganShift(String shiftId) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: 'k-1',
        username: 'sari',
        role: 'cashier',
        shiftId: shiftId,
        permissions: const ['create_transaction', 'open_close_shift'],
      ));

  Future<void> shift(String id, {DateTime? tutup, String? keShift}) =>
      db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: Value(id),
            userId: 'k-1',
            endAt: Value(tutup),
            digabungKe: Value(keShift),
            deletedAt: Value(keShift == null ? null : DateTime.now()),
          ));

  final teh = SaleLine(
      productId: 'teh', productName: 'Teh', qty: 1, priceAtSale: 5000);

  test('nomor 23: bill baru TIDAK masuk ke shift yang sudah ditutup', () async {
    await shift('s-1', tutup: DateTime.now());
    await masukDenganShift('s-1');
    await expectLater(
      OpenBillRepository(db).simpan(nama: 'Meja 1', baris: [teh]),
      throwsA(isA<ShiftSudahDitutup>()),
    );
    expect(await db.select(db.openBills).get(), isEmpty);
  });

  test('nomor 23: bill dari shift yang digabung masuk ke shift tujuan',
      () async {
    await shift('s-a');
    await shift('s-b', keShift: 's-a');
    await masukDenganShift('s-b');
    await OpenBillRepository(db).simpan(nama: 'Meja 1', baris: [teh]);
    expect((await db.select(db.openBills).getSingle()).shiftId, 's-a');
  });

  test('nomor 29: shift yang digabung TIDAK dianggap ditutup saat bayar',
      () async {
    await shift('s-a');
    await shift('s-b', keShift: 's-a');
    expect(await db.shiftBerjalan('s-b'), 's-a');
    await shift('s-c', tutup: DateTime.now());
    await expectLater(
        db.shiftBerjalan('s-c'), throwsA(isA<ShiftSudahDitutup>()));
  });

  test('nomor 29: tutup shift menutup shift tujuan penggabungan', () async {
    await shift('s-a');
    await shift('s-b', keShift: 's-a');
    final repo = ShiftRepository(db);
    expect(await repo.ujungShift('s-b'), 's-a');
  });

  test('nomor 30: shift yang belum ada di HP memberi pesan yang jelas',
      () async {
    await masukDenganShift('s-hilang');
    await expectLater(
      db.createSale(
        transactionId: 'tx-1',
        lines: [teh],
        paymentMethod: 'cash',
        orderType: 'dine_in',
        cashReceived: 5000,
        cashierUserId: 'k-1',
        shiftId: 's-hilang',
        kodePerangkat: 'A',
      ),
      throwsA(isA<ShiftBelumAda>()),
    );
  });
}
