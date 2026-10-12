import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/nama_tercatat.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hapus Akun (keputusan owner 2026-10-07): permanen, tidak muncul lagi di
/// mana pun, username bebas dipakai ulang, riwayat lama tetap utuh dengan
/// nama "… (dihapus)".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CashierRepository repo;
  var online = true;
  const pin = '112233';

  Future<User> akun(String id) =>
      (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();

  Future<void> masukOwner() => SessionManager.instance.setSession(
    AuthSession.create(
      userId: 'o-1',
      username: 'owner',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    online = true;
    repo = CashierRepository(
      db,
      namaDipakaiDiServer: (_, _) async => false,
      terhubung: () async => online,
    );
    final salt = CryptoUtils.generateSalt();
    for (final (id, nama, role) in const [
      ('o-1', 'owner', 'owner'),
      ('8f3a91c2-0000-4000-8000-000000000001', 'sari', 'cashier'),
    ]) {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: Value(id),
              username: nama,
              pinHash: CryptoUtils.hashPin(pin, salt),
              salt: salt,
              role: role,
            ),
          );
    }
    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: const Value('s-jalan'),
            userId: '8f3a91c2-0000-4000-8000-000000000001',
            userName: const Value('sari'),
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: const Value('t-lama'),
            total: 1000,
            paymentMethod: 'cash',
            cashierUserId: const Value('8f3a91c2-0000-4000-8000-000000000001'),
            cashierName: const Value('sari'),
          ),
        );
    await masukOwner();
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  const idSari = '8f3a91c2-0000-4000-8000-000000000001';

  test(
    'hapus: ditandai, dinonaktifkan, username dilepas, shift diakhiri',
    () async {
      await repo.hapusKasir(idSari);
      final a = await akun(idSari);
      expect(a.deletedAt, isNotNull);
      expect(a.isActive, isFalse, reason: 'HP dengan APK lama tetap menolak');
      expect(a.username, 'sari~8f3a91c2');
      expect(a.syncStatus, 'pending');
      final s = await db.select(db.shifts).getSingle();
      expect(s.endAt, isNotNull);
      expect(s.syncStatus, 'pending');
      expect(
        await repo.getAllCashiers(),
        isEmpty,
        reason: 'hilang dari daftar',
      );
    },
  );

  test('tanpa internet: hapus ditolak, tidak ada yang berubah', () async {
    online = false;
    await expectLater(repo.hapusKasir(idSari), throwsA(isA<StateError>()));
    expect((await akun(idSari)).deletedAt, isNull);
  });

  test('hanya owner yang boleh menghapus', () async {
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: idSari,
        username: 'sari',
        role: 'cashier',
        shiftId: 's-jalan',
        permissions: const ['create_transaction'],
      ),
    );
    await expectLater(repo.hapusKasir(idSari), throwsA(anything));
    expect((await akun(idSari)).deletedAt, isNull);
  });

  test(
    'username bekas dipakai karyawan baru; riwayat tetap terpisah',
    () async {
      await repo.hapusKasir(idSari);
      final baru = await repo.createCashier(username: 'sari', pin: '727272');
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: const Value('t-baru'),
              total: 2000,
              paymentMethod: 'cash',
              cashierUserId: Value(baru.id),
              cashierName: const Value('sari'),
            ),
          );
      final nama = await db.namaAkun();
      final trx = {
        for (final t in await db.select(db.transactions).get()) t.id: t,
      };
      expect(trx['t-lama']!.namaKasir(nama), 'sari (dihapus)');
      expect(trx['t-baru']!.namaKasir(nama), 'sari');
    },
  );

  test(
    'catatan tanpa salinan dari akun yang dihapus tetap bernama asli',
    () async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: const Value('e-hp-lama'),
              userId: idSari,
              description: 'Es',
              amount: 5000,
            ),
          );
      await repo.hapusKasir(idSari);
      final e = await db.select(db.expenses).getSingle();
      expect(e.userName, isNull);
      expect(e.namaPencatat(await db.namaAkun()), 'sari (dihapus)');
    },
  );

  test(
    'login, daftar nama login, dan sesi berjalan menolak akun dihapus',
    () async {
      final auth = AuthRepository(db);
      final sesi = await auth.login(username: 'sari', pin: pin);
      expect(sesi, isNotNull);
      await SessionManager.instance.setSession(sesi!);

      // Owner menghapus dari HP lain; datanya tiba lewat sinkron.
      await (db.update(db.users)..where((u) => u.id.equals(idSari))).write(
        UsersCompanion(deletedAt: Value(DateTime.now())),
      );
      await SessionManager.instance.periksaAkunMasihBerlaku();
      expect(SessionManager.instance.currentSession, isNull);
      expect(await auth.getAllActiveUsernames(), ['owner']);
      await expectLater(
        auth.login(username: 'sari', pin: pin),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'pesan',
            'Akun Anda sudah dihapus oleh pemilik.',
          ),
        ),
      );
    },
  );
}
