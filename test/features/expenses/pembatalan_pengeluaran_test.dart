import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengeluaran tidak bisa diedit dan tidak pernah dihapus — hanya
/// DIBATALKAN, dengan aturan yang sama dengan transaksi.
///
/// Dulu `deleteExpense` tidak memeriksa izin sama sekali dan tombol hapus
/// muncul untuk semua pengeluaran di shift aktif; kasir juga bisa mengubah
/// jumlahnya tanpa jejak.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpenseRepository repo;
  const pinOwner = '135790';

  Future<void> masuk(String id, String role, {String? shiftId}) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: id,
        username: id,
        role: role,
        shiftId: shiftId,
        permissions: const [],
      ));

  Future<Expense> pengeluaran(String id,
      {String user = 'budi', String shift = 's-aktif'}) async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: Value(id),
          shiftId: Value(shift),
          userId: user,
          description: 'Es batu',
          amount: 5000,
        ));
    return (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = ExpenseRepository(db);
    for (final (id, role, pin) in [
      ('owner', 'owner', pinOwner),
      ('budi', 'cashier', '111111'),
      ('sari', 'cashier', '222222'),
    ]) {
      final garam = CryptoUtils.generateSalt();
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: id,
            pinHash: CryptoUtils.hashPin(pin, garam),
            salt: garam,
            role: role,
          ));
    }
    for (final (id, user) in [('s-aktif', 'budi'), ('s-lama', 'budi')]) {
      await db.into(db.shifts).insert(
          ShiftsCompanion.insert(id: Value(id), userId: user));
    }
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test('kasir membatalkan pengeluarannya di shift berjalan dengan PIN owner',
      () async {
    final e = await pengeluaran('e-1');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    expect(repo.bolehDibatalkan(e), isTrue);
    await expectLater(repo.batalkanPengeluaran(e, alasan: 'Salah input'),
        throwsA(isA<StateError>()), reason: 'tanpa PIN ditolak');
    await repo.batalkanPengeluaran(e,
        alasan: 'Tercatat dobel', pinOwner: pinOwner);

    final batal = await (db.select(db.expenses)
          ..where((x) => x.id.equals('e-1')))
        .getSingle();
    expect(batal.deletedAt, isNotNull);
    expect(batal.cancelledByUserId, 'budi');
    expect(batal.cancelReason, 'Tercatat dobel');
  });

  test('kasir tidak bisa membatalkan pengeluaran shift lain atau akun lain',
      () async {
    final lama = await pengeluaran('e-lama', shift: 's-lama');
    final punyaSari = await pengeluaran('e-sari', user: 'sari');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    expect(repo.bolehDibatalkan(lama), isFalse);
    expect(repo.bolehDibatalkan(punyaSari), isFalse,
        reason: 'dulu tombol hapus muncul untuk SEMUA pengeluaran di shift');
    await expectLater(
        repo.batalkanPengeluaran(punyaSari,
            alasan: 'Salah input', pinOwner: pinOwner),
        throwsA(isA<StateError>()));
  });

  test('owner membatalkan pengeluaran apa pun tanpa PIN', () async {
    final lama = await pengeluaran('e-lama', shift: 's-lama');
    await masuk('owner', 'owner');

    expect(repo.perluPinOwner, isFalse);
    await repo.batalkanPengeluaran(lama, alasan: 'Tidak jadi dibeli');
    final batal = await (db.select(db.expenses)
          ..where((x) => x.id.equals('e-lama')))
        .getSingle();
    expect(batal.cancelledByUserId, 'owner');
  });

  test('kunci PIN salah DIPAKAI BERSAMA dengan pembatalan transaksi',
      () async {
    // Kalau kuncinya terpisah, kasir bisa menebak 4 kali di transaksi lalu
    // 4 kali lagi di pengeluaran.
    final e = await pengeluaran('e-1');
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('t-1'),
          cashierUserId: const Value('budi'),
          shiftId: const Value('s-aktif'),
          total: 10000,
          paymentMethod: 'cash',
        ));
    final t = await db.select(db.transactions).getSingle();
    await masuk('budi', 'cashier', shiftId: 's-aktif');
    final sales = SalesRepository(db);

    for (var i = 0; i < 3; i++) {
      await expectLater(
          sales.batalkanTransaksi(t, alasan: 'x', pinOwner: '000000'),
          throwsA(isA<StateError>()));
    }
    for (var i = 0; i < 2; i++) {
      await expectLater(
          repo.batalkanPengeluaran(e, alasan: 'x', pinOwner: '000000'),
          throwsA(isA<StateError>()));
    }
    await expectLater(
        repo.batalkanPengeluaran(e, alasan: 'x', pinOwner: pinOwner),
        throwsA(isA<StateError>()
            .having((x) => x.message, 'pesan', contains('Terlalu banyak'))));
  });
}
