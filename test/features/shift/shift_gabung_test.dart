import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Revisi QA K9: satu akun membuka shift di dua HP yang sama-sama offline.
/// Server menggabung shift yang datang belakangan (B) ke yang lebih dulu (A)
/// — supabase/shift_gabung.sql. Di sini: sisi HP yang shift-nya digabung.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    for (final id in ['s-a', 's-b']) {
      await db
          .into(db.shifts)
          .insert(ShiftsCompanion.insert(id: Value(id), userId: 'k-1'));
    }
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: const Value('teh'),
            name: 'Teh',
            price: 8000,
          ),
        );
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'k-1',
        username: 'sari',
        role: 'cashier',
        shiftId: 's-b',
        permissions: const ['create_transaction'],
      ),
    );
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  /// Keadaan sesudah HP ini menarik kabar penggabungan dari server.
  Future<void> bDigabungKeA() =>
      (db.update(db.shifts)..where((s) => s.id.equals('s-b'))).write(
        ShiftsCompanion(
          digabungKe: const Value('s-a'),
          deletedAt: Value(DateTime.now()),
        ),
      );

  Future<void> tutupA() =>
      (db.update(db.shifts)..where((s) => s.id.equals('s-a'))).write(
        ShiftsCompanion(endAt: Value(DateTime.now())),
      );

  Future<void> jualTeh() => SalesRepository(db).createSale(
    transactionId: 'tx-1',
    lines: [
      SaleLine(productId: 'teh', productName: 'Teh', qty: 1, priceAtSale: 8000),
    ],
    paymentMethod: 'qris',
    orderType: 'dine_in',
    cashierUserId: 'k-1',
    shiftId: 's-b',
  );

  group('penjualan & pengeluaran ke shift yang digabung', () {
    test('masuk ke shift tujuan, bukan ditolak', () async {
      await bDigabungKeA();
      await jualTeh();
      await ExpenseRepository(db).addExpense(
        shiftId: 's-b',
        userId: 'k-1',
        description: 'Es batu',
        amount: 5000,
      );
      expect((await db.select(db.transactions).getSingle()).shiftId, 's-a');
      expect((await db.select(db.expenses).getSingle()).shiftId, 's-a');
    });

    test('shift tujuan sudah ditutup: ditolak seperti biasa', () async {
      await bDigabungKeA();
      await tutupA();
      await expectLater(jualTeh(), throwsA(isA<ShiftSudahDitutup>()));
      expect(await db.select(db.transactions).get(), isEmpty);
    });
  });

  group('sesi kasir', () {
    test(
      'pindah ke shift tujuan, kasir diberi tahu, tidak dikeluarkan',
      () async {
        await bDigabungKeA();
        await SessionManager.instance.periksaShiftMasihBerjalan();
        expect(SessionManager.instance.currentSession?.shiftId, 's-a');
        expect(SessionManager.instance.shiftDigabung.value, isNotNull);
        expect(SessionManager.instance.shiftDitutupDariLuar.value, isNull);
        SessionManager.instance.shiftDigabung.value = null;
      },
    );

    test('shift tujuan sudah ditutup: dilepas seperti shift ditutup', () async {
      await bDigabungKeA();
      await tutupA();
      await SessionManager.instance.periksaShiftMasihBerjalan();
      expect(SessionManager.instance.currentSession?.shiftId, isNull);
      expect(SessionManager.instance.shiftDitutupDariLuar.value, isNotNull);
      SessionManager.instance.shiftDitutupDariLuar.value = null;
      SessionManager.instance.shiftDigabung.value = null;
    });
  });

  group('sinkron', () {
    Map<String, dynamic> barisServer({Object? digabungKe = _tanpa}) => {
      'id': 's-b',
      'user_id': 'k-1',
      'start_at': '2026-10-29T01:03:00Z',
      'end_at': null,
      'kas_awal': 100000,
      'updated_at': '2099-01-01T00:00:00Z',
      'deleted_at': '2026-10-29T02:00:00Z',
      'server_urut': '2026-10-29T02:00:00Z',
      if (digabungKe != _tanpa) 'digabung_ke': digabungKe,
    };

    Future<String?> tujuanLokal() async => (await (db.select(
      db.shifts,
    )..where((s) => s.id.equals('s-b'))).getSingle()).digabungKe;

    test('tarik: tujuan gabungan dari server tersimpan di HP', () async {
      final mesin = SyncEngine(db)
        ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
            tabel == 'shifts' && setelah == null
            ? [barisServer(digabungKe: 's-a')]
            : const [];
      await mesin.tarikTabel('shifts');
      expect(await tujuanLokal(), 's-a');
    });

    test('tarik dari server tanpa shift_gabung.sql: tidak gagal', () async {
      final mesin = SyncEngine(db)
        ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
            tabel == 'shifts' && setelah == null ? [barisServer()] : const [];
      await mesin.tarikTabel('shifts');
      expect(await tujuanLokal(), isNull);
    });

    test(
      'kirim: digabung_ke TIDAK pernah dikirim — itu urusan server',
      () async {
        final terkirim = <Map<String, dynamic>>[];
        final mesin = SyncEngine(db)
          ..pengirimUntukTest = (tabel, baris) async {
            if (tabel == 'shifts') terkirim.addAll(baris);
          };
        await bDigabungKeA();
        await mesin.dorongSemua();
        expect(terkirim, isNotEmpty);
        expect(terkirim.every((b) => !b.containsKey('digabung_ke')), isTrue);
      },
    );
  });

  test(
    'migrasi v41 → v42: kolom ditambah, hanya penanda shifts dikosongkan',
    () async {
      final folder = Directory.systemTemp.createTempSync('uji_v42');
      addTearDown(() => folder.deleteSync(recursive: true));
      final jalur = '${folder.path}/v41.sqlite';

      final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      await lama
          .into(lama.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('k-1'),
              username: 'sari',
              pinHash: 'h',
              salt: 's',
              role: 'cashier',
            ),
          );
      await lama
          .into(lama.shifts)
          .insert(
            ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'),
          );
      for (final t in ['shifts', 'transactions']) {
        await lama
            .into(lama.syncState)
            .insert(
              SyncStateCompanion.insert(
                entity: t,
                lastPulledCursor: const Value('2026-10-28T10:00:00+00:00'),
              ),
            );
      }
      await lama.close();

      // Keadaan HP yang masih v41: kolomnya belum ada.
      final mentah = sqlite3.open(jalur);
      mentah.execute('ALTER TABLE shifts DROP COLUMN digabung_ke');
      mentah.execute('PRAGMA user_version = 41');
      mentah.dispose();

      final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      addTearDown(baru.close);
      expect((await baru.select(baru.shifts).getSingle()).digabungKe, isNull);
      final penanda = {
        for (final p in await baru.select(baru.syncState).get())
          p.entity: p.lastPulledCursor,
      };
      expect(penanda['shifts'], isNull);
      expect(penanda['transactions'], isNotNull);
    },
  );
}

const _tanpa = Object();
