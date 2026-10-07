import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/data/nama_tercatat.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v35: setiap shift, transaksi, dan pengeluaran menyimpan SALINAN nama akun
/// saat dibuat, supaya riwayat lama tidak ikut berubah ketika akunnya diganti
/// nama atau dihapus (username bekas boleh dipakai ulang — keputusan owner
/// 2026-10-07).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> akun(AppDatabase db, String id, String nama, String role) => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: Value(id),
          username: nama,
          pinHash: 'h',
          salt: 's',
          role: role,
        ),
      );

  test(
    'migrasi v34 → v35: kolom ada, data lama terisi, tidak dikirim ulang',
    () async {
      final folder = Directory.systemTemp.createTempSync('uji_v35');
      addTearDown(() => folder.deleteSync(recursive: true));
      final jalur = '${folder.path}/v34.sqlite';

      final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      await akun(lama, 'k-1', 'sari', 'cashier');
      await akun(lama, 'o-1', 'owner', 'owner');
      await lama
          .into(lama.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s-1'),
              userId: 'k-1',
              syncStatus: const Value('synced'),
            ),
          );
      await lama
          .into(lama.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: const Value('t-1'),
              total: 1000,
              paymentMethod: 'cash',
              cashierUserId: const Value('k-1'),
              shiftId: const Value('s-1'),
              deletedAt: Value(DateTime(2026, 10, 1)),
              cancelledByUserId: const Value('o-1'),
              syncStatus: const Value('synced'),
            ),
          );
      await lama
          .into(lama.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: const Value('e-1'),
              userId: 'k-1',
              description: 'Es',
              amount: 5000,
              syncStatus: const Value('synced'),
            ),
          );
      await lama.close();

      // Keadaan v34: kolom-kolom v35 belum ada.
      final mentah = sqlite3.open(jalur);
      for (final (tabel, kolom) in const [
        ('users', 'deleted_at'),
        ('shifts', 'user_name'),
        ('transactions', 'cashier_name'),
        ('transactions', 'cancelled_by_name'),
        ('expenses', 'user_name'),
        ('expenses', 'cancelled_by_name'),
      ]) {
        mentah.execute('ALTER TABLE $tabel DROP COLUMN $kolom');
      }
      mentah.execute('PRAGMA user_version = 34');
      mentah.dispose();

      final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      addTearDown(baru.close);
      Future<List<String>> kolom(String t) async => [
        for (final r
            in await baru
                .customSelect("SELECT name FROM pragma_table_info('$t')")
                .get())
          r.read<String>('name'),
      ];
      expect(await kolom('users'), contains('deleted_at'));
      expect(await kolom('shifts'), contains('user_name'));
      expect(
        await kolom('transactions'),
        containsAll(['cashier_name', 'cancelled_by_name']),
      );
      expect(
        await kolom('expenses'),
        containsAll(['user_name', 'cancelled_by_name']),
      );

      final s = await baru.select(baru.shifts).getSingle();
      final t = await baru.select(baru.transactions).getSingle();
      final e = await baru.select(baru.expenses).getSingle();
      expect(s.userName, 'sari');
      expect((t.cashierName, t.cancelledByName), ('sari', 'owner'));
      expect((e.userName, e.cancelledByName), ('sari', null));
      expect(
        [s.syncStatus, t.syncStatus, e.syncStatus],
        everyElement('synced'),
        reason: 'isinya sama dengan hasil SQL server — tidak perlu dikirim',
      );
    },
  );

  group('salinan nama saat data dibuat', () {
    late AppDatabase db;

    Future<void> masukSebagai(String id, String role, List<String> izin) =>
        SessionManager.instance.setSession(
          AuthSession.create(
            userId: id,
            username: id,
            role: role,
            shiftId: role == 'cashier' ? 's-1' : null,
            permissions: izin,
          ),
        );
    Future<void> masukKasir() =>
        masukSebagai('k-1', 'cashier', const ['create_transaction']);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
      await akun(db, 'k-1', 'sari', 'cashier');
      await akun(db, 'o-1', 'owner', 'owner');
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: const Value('p-1'),
              name: 'Nasi Goreng',
              price: 15000,
            ),
          );
      await masukKasir();
    });
    tearDown(() async {
      await SessionManager.instance.clearSession();
      SessionManager.dbOverride = null;
      await db.close();
    });

    Future<Transaction> jual(String id) async {
      await db.createSale(
        transactionId: id,
        paymentMethod: 'qris',
        orderType: 'dine_in',
        cashierUserId: 'k-1',
        shiftId: 's-1',
        lines: [
          SaleLine(
            productId: 'p-1',
            productName: 'Nasi Goreng',
            qty: 1,
            priceAtSale: 15000,
          ),
        ],
        kodePerangkat: 'TEST',
      );
      return (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
    }

    test('transaksi, pengeluaran, dan pembatalan menyimpan nama', () async {
      final t = await jual('t-1');
      expect(t.cashierName, 'sari');

      await db.addExpense(
        shiftId: 's-1',
        userId: 'k-1',
        description: 'Es',
        amount: 5000,
      );
      final e = await db.select(db.expenses).getSingle();
      expect(e.userName, 'sari');

      await db.batalkanTransaksi('t-1', olehUserId: 'o-1', alasan: 'x');
      await db.batalkanPengeluaran(e.id, olehUserId: 'o-1', alasan: 'y');
      final t2 = await (db.select(
        db.transactions,
      )..where((x) => x.id.equals('t-1'))).getSingle();
      final e2 = await db.select(db.expenses).getSingle();
      expect(t2.cancelledByName, 'owner');
      expect(e2.cancelledByName, 'owner');
    });

    test('Ubah Username: riwayat lama tetap memakai nama lama', () async {
      final lama = await jual('t-lama');
      await masukSebagai('o-1', 'owner', const []);
      await CashierRepository(
        db,
        namaDipakaiDiServer: (_, _) async => false,
        terhubung: () async => true,
      ).gantiNamaKasir('k-1', 'sari.w');

      final nama = await db.namaAkun();
      final lamaLagi = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(lama.id))).getSingle();
      expect(
        lamaLagi.namaKasir(nama),
        'sari',
        reason: 'riwayat tidak ikut berubah',
      );

      await masukKasir();
      final baru = await jual('t-baru');
      expect(baru.namaKasir(nama), 'sari.w');
    });

    test('catatan tanpa salinan (dari HP lama) memakai nama akun', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: const Value('t-lama-hp'),
              total: 1000,
              paymentMethod: 'cash',
              cashierUserId: const Value('k-1'),
            ),
          );
      final t = await (db.select(
        db.transactions,
      )..where((x) => x.id.equals('t-lama-hp'))).getSingle();
      expect(t.cashierName, isNull);
      expect(t.namaKasir(await db.namaAkun()), 'sari');
    });
  });

  test('membuka shift saat login menyimpan nama kasir', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const pin = '112233';
    final salt = CryptoUtils.generateSalt();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'budi',
            pinHash: CryptoUtils.hashPin(pin, salt),
            salt: salt,
            role: 'cashier',
          ),
        );
    final sesi = await AuthRepository(db).login(username: 'budi', pin: pin);
    final s = await (db.select(
      db.shifts,
    )..where((x) => x.id.equals(sesi!.shiftId!))).getSingle();
    expect(s.userName, 'budi');
    await SessionManager.instance.clearSession();
  });

  group('sinkron', () {
    late AppDatabase db;
    late SyncEngine mesin;
    late List<Map<String, dynamic>> server;
    final terkirim = <Map<String, dynamic>>[];

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await akun(db, 'k-1', 'sari', 'cashier');
      server = [];
      terkirim.clear();
      mesin = SyncEngine(db)
        ..penarikUntukTest = ((tabel, kolom, sejak, setelah, batas) async =>
            tabel == 'shifts' ? server : const <Map<String, dynamic>>[])
        ..pengirimUntukTest = (tabel, baris) async {
          if (tabel == 'shifts') terkirim.addAll(baris);
        };
    });
    tearDown(() => db.close());

    test('salinan nama ikut dikirim', () async {
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s-1'),
              userId: 'k-1',
              userName: const Value('sari'),
            ),
          );
      await mesin.dorongSemua();
      expect(terkirim.single['user_name'], 'sari');
    });

    test('server tanpa salinan TIDAK mengosongkan salinan di HP', () async {
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s-1'),
              userId: 'k-1',
              userName: const Value('sari'),
              updatedAt: Value(DateTime(2026, 10, 1)),
              syncStatus: const Value('synced'),
            ),
          );
      final diubah = DateTime.utc(2026, 10, 2).toIso8601String();
      server = [
        {
          'id': 's-1',
          'user_id': 'k-1',
          // Kolom user_name tidak ada: server belum menjalankan SQL-nya.
          'start_at': diubah,
          'end_at': diubah,
          'updated_at': diubah,
          'deleted_at': null,
          'server_urut': diubah,
        },
      ];
      await mesin.tarikTabel('shifts');
      final s = await db.select(db.shifts).getSingle();
      expect(s.endAt, isNotNull, reason: 'baris server memang diterima');
      expect(s.userName, 'sari');
    });
  });
}
