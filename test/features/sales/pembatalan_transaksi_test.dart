import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Transaksi tidak pernah dihapus, hanya DIBATALKAN — dengan siapa, kapan,
/// dan alasannya — dan disimpan selamanya.
///
/// Dulu tombolnya "Hapus Transaksi": kasir bisa menghapus transaksinya kapan
/// saja tanpa alasan, dan transaksi itu hilang dari semua tampilan. Owner
/// tidak punya cara tahu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalesRepository repo;
  const pinOwner = '135790';

  Future<void> masuk(String id, String role, {String? shiftId}) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: id,
        username: id,
        role: role,
        shiftId: shiftId,
        permissions: const ['create_transaction'],
      ));

  Future<Transaction> trx(String id, {String kasir = 'budi', String shift = 's-aktif'}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: Value(id),
          cashierUserId: Value(kasir),
          shiftId: Value(shift),
          total: 20000,
          paymentMethod: 'cash',
          syncStatus: const Value('synced'),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: Value('$id-item'),
          transactionId: id,
          productId: 'p-kopi',
          productName: const Value('Kopi'),
          qty: 2,
          priceAtSale: 10000,
          subtotal: 20000,
        ));
    return (db.select(db.transactions)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<Transaction> ambil(String id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = SalesRepository(db);

    final garam = CryptoUtils.generateSalt();
    for (final (id, role, pin) in [
      ('owner', 'owner', pinOwner),
      ('budi', 'cashier', '111111'),
      ('sari', 'cashier', '222222'),
    ]) {
      final s = id == 'owner' ? garam : CryptoUtils.generateSalt();
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: id,
            pinHash: CryptoUtils.hashPin(pin, s),
            salt: s,
            role: role,
          ));
    }
    for (final (id, user) in [('s-aktif', 'budi'), ('s-lama', 'budi'), ('s-sari', 'sari')]) {
      await db.into(db.shifts).insert(
          ShiftsCompanion.insert(id: Value(id), userId: user));
    }
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test('kasir membatalkan transaksinya di shift berjalan dengan PIN owner',
      () async {
    final t = await trx('t-1');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    expect(repo.bolehDibatalkan(t), isTrue);
    expect(repo.perluPinOwner, isTrue);
    await repo.batalkanTransaksi(t, alasan: 'Salah input', pinOwner: pinOwner);

    final batal = await ambil('t-1');
    expect(batal.deletedAt, isNotNull, reason: 'keluar dari semua total');
    expect(batal.cancelledByUserId, 'budi');
    expect(batal.cancelReason, 'Salah input');
    expect(batal.syncStatus, 'pending');

    final item = await repo.getTransactionItems('t-1', termasukBatal: true);
    expect(item.single.productName, 'Kopi',
        reason: 'isi struk yang dibatalkan tetap bisa dilihat sebagai bukti');
  });

  test('tanpa PIN atau dengan PIN salah, kasir ditolak', () async {
    final t = await trx('t-1');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    await expectLater(repo.batalkanTransaksi(t, alasan: 'Salah input'),
        throwsA(isA<StateError>()));
    await expectLater(
        repo.batalkanTransaksi(t, alasan: 'Salah input', pinOwner: '111111'),
        throwsA(isA<StateError>()),
        reason: 'PIN kasir sendiri bukan PIN owner');
    expect((await ambil('t-1')).deletedAt, isNull);
  });

  test('kasir tidak bisa membatalkan transaksi shift lain atau kasir lain',
      () async {
    final lama = await trx('t-lama', shift: 's-lama');
    final punyaSari = await trx('t-sari', kasir: 'sari', shift: 's-aktif');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    expect(repo.bolehDibatalkan(lama), isFalse,
        reason: 'shift yang sudah ditutup hanya bisa diubah owner');
    expect(repo.bolehDibatalkan(punyaSari), isFalse);
    await expectLater(
        repo.batalkanTransaksi(lama, alasan: 'Salah input', pinOwner: pinOwner),
        throwsA(isA<StateError>()));
  });

  test('owner membatalkan transaksi apa pun tanpa PIN', () async {
    final lama = await trx('t-lama', shift: 's-lama');
    await masuk('owner', 'owner');

    expect(repo.bolehDibatalkan(lama), isTrue);
    expect(repo.perluPinOwner, isFalse);
    await repo.batalkanTransaksi(lama, alasan: 'Pelanggan batal');
    expect((await ambil('t-lama')).cancelledByUserId, 'owner');
  });

  test('alasan wajib, dan transaksi batal tidak bisa dibatalkan lagi',
      () async {
    final t = await trx('t-1');
    await masuk('owner', 'owner');

    await expectLater(repo.batalkanTransaksi(t, alasan: '   '),
        throwsA(isA<ArgumentError>()));
    await repo.batalkanTransaksi(t, alasan: 'Pelanggan batal');
    final batal = await ambil('t-1');
    expect(repo.bolehDibatalkan(batal), isFalse);
    await expectLater(repo.batalkanTransaksi(batal, alasan: 'Lagi'),
        throwsA(isA<StateError>()));
  });

  test('5 kali PIN salah mengunci pembatalan di HP ini, bukan login owner',
      () async {
    final t = await trx('t-1');
    await masuk('budi', 'cashier', shiftId: 's-aktif');

    for (var i = 0; i < 5; i++) {
      await expectLater(
          repo.batalkanTransaksi(t, alasan: 'Salah input', pinOwner: '000000'),
          throwsA(isA<StateError>()));
    }
    await expectLater(
        repo.batalkanTransaksi(t, alasan: 'Salah input', pinOwner: pinOwner),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'pesan', contains('Terlalu banyak'))),
        reason: 'PIN benar pun ditolak selama terkunci');

    final owner = await (db.select(db.users)
          ..where((u) => u.id.equals('owner')))
        .getSingle();
    expect(owner.loginLockedUntil, isNull,
        reason: 'kasir yang menebak PIN tidak boleh bisa mengunci owner');
  });

  test('transaksi batal tampil di Riwayat tapi tidak di kueri laporan',
      () async {
    final t = await trx('t-1');
    await trx('t-2');
    await masuk('owner', 'owner');
    await repo.batalkanTransaksi(t, alasan: 'Salah input');

    final laporan = await db.watchTransactions().first;
    final riwayat = await db.watchTransactions(termasukBatal: true).first;
    expect(laporan.map((x) => x.id), ['t-2']);
    expect(riwayat.map((x) => x.id).toSet(), {'t-1', 't-2'});
  });
}
