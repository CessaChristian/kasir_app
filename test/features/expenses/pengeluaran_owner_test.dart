import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/expenses/widgets/dialog_pengeluaran.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Owner boleh mencatat pengeluaran TANPA shift (v33); kasir tetap wajib
/// pada shift berjalan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> isiAwal(AppDatabase db) async {
    for (final (id, role) in [('owner', 'owner'), ('budi', 'cashier')]) {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: Value(id),
              username: id,
              pinHash: 'h',
              salt: 's',
              role: role,
            ),
          );
    }
    await db
        .into(db.shifts)
        .insert(ShiftsCompanion.insert(id: const Value('s-1'), userId: 'budi'));
  }

  Future<void> masuk(String id, String role, {String? shiftId}) =>
      SessionManager.instance.setSession(
        AuthSession.create(
          userId: id,
          username: id,
          role: role,
          shiftId: shiftId,
          permissions: const ['create_transaction'],
        ),
      );

  group('aturan pencatatan', () {
    late AppDatabase db;
    late ExpenseRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
      repo = ExpenseRepository(db);
      await isiAwal(db);
    });

    tearDown(() async {
      await SessionManager.instance.clearSession();
      SessionManager.dbOverride = null;
      await db.close();
    });

    test('owner mencatat tanpa shift', () async {
      await masuk('owner', 'owner');
      await repo.addExpense(
        shiftId: null,
        userId: 'owner',
        description: 'Bayar listrik',
        amount: 150000,
        category: 'operasional_kedai',
      );
      final e = await db.select(db.expenses).getSingle();
      expect(e.shiftId, isNull);
      expect(e.userId, 'owner');
      expect(e.syncStatus, 'pending');
    });

    test('kasir tanpa shift ditolak; dengan shift berjalan boleh', () async {
      await masuk('budi', 'cashier', shiftId: 's-1');
      expect(
        () => repo.addExpense(
          shiftId: null,
          userId: 'budi',
          description: 'x',
          amount: 1,
        ),
        throwsA(isA<StateError>()),
      );
      await repo.addExpense(
        shiftId: 's-1',
        userId: 'budi',
        description: 'Es batu',
        amount: 5000,
      );
      expect((await db.select(db.expenses).get()).single.shiftId, 's-1');
    });

    test('kasir tidak bisa membatalkan pengeluaran owner', () async {
      await masuk('owner', 'owner');
      await repo.addExpense(
        shiftId: null,
        userId: 'owner',
        description: 'Gas',
        amount: 25000,
      );
      final e = await db.select(db.expenses).getSingle();
      await masuk('budi', 'cashier', shiftId: 's-1');
      expect(repo.bolehDibatalkan(e), isFalse);
      await masuk('owner', 'owner');
      expect(repo.bolehDibatalkan(e), isTrue);
    });

    test(
      'pengeluaran owner dari server (tanpa shift) diterima sinkron',
      () async {
        final hasil = await SyncEngine(db).gabungkanTabel('expenses', [
          {
            'id': 'e-owner',
            'shift_id': null,
            'user_id': 'owner',
            'description': 'Bayar listrik',
            'amount': 150000,
            'category': 'operasional_kedai',
            'qty': 1,
            'created_at': '2026-10-04T08:00:00+00:00',
            'updated_at': '2026-10-04T08:00:00+00:00',
            'deleted_at': null,
            'cancelled_by_user_id': null,
            'cancel_reason': null,
            'server_urut': '2026-10-04T08:00:00+00:00',
          },
        ]);
        expect(hasil, (1, 1));
        expect((await db.select(db.expenses).getSingle()).shiftId, isNull);
      },
    );
  });

  test(
    'migrasi v32 → v33: shift_id boleh kosong, isi dan pagar utuh',
    () async {
      SharedPreferences.setMockInitialValues({});
      final folder = Directory.systemTemp.createTempSync('uji_v33');
      addTearDown(() => folder.deleteSync(recursive: true));
      final jalur = '${folder.path}/v32.sqlite';

      final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      await isiAwal(lama);
      await lama
          .into(lama.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: const Value('e-lama'),
              shiftId: const Value('s-1'),
              userId: 'budi',
              description: 'Es batu',
              amount: 5000,
              category: const Value('asset'),
              qty: const Value(2),
            ),
          );
      await lama.close();

      // Keadaan v32: shift_id masih NOT NULL.
      final mentah = sqlite3.open(jalur);
      mentah.execute('PRAGMA foreign_keys = OFF');
      mentah.execute('ALTER TABLE expenses RENAME TO expenses_baru');
      mentah.execute(
        "CREATE TABLE expenses (id TEXT NOT NULL PRIMARY KEY, "
        "shift_id TEXT NOT NULL REFERENCES shifts (id), "
        "user_id TEXT NOT NULL REFERENCES users (id), "
        "description TEXT NOT NULL, amount INTEGER NOT NULL, "
        "category TEXT NOT NULL DEFAULT 'bahan_baku' "
        "CHECK (category IN ('asset', 'bahan_baku', 'operasional_kedai')), "
        "qty INTEGER NOT NULL DEFAULT 1 CHECK (qty >= 1), "
        "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, "
        "deleted_at INTEGER NULL, "
        "cancelled_by_user_id TEXT NULL REFERENCES users (id), "
        "cancel_reason TEXT NULL, sync_status TEXT NOT NULL DEFAULT 'pending')",
      );
      mentah.execute('INSERT INTO expenses SELECT * FROM expenses_baru');
      mentah.execute('DROP TABLE expenses_baru');
      mentah.execute('PRAGMA user_version = 32');
      final notnull = mentah
          .select(
            "SELECT \"notnull\" FROM pragma_table_info('expenses') "
            "WHERE name = 'shift_id'",
          )
          .single['notnull'];
      expect(notnull, 1, reason: 'prasyarat: keadaan v32 sungguh NOT NULL');
      mentah.dispose();

      final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      addTearDown(baru.close);
      final kolom = await baru
          .customSelect(
            "SELECT \"notnull\" AS nn FROM pragma_table_info('expenses') "
            "WHERE name = 'shift_id'",
          )
          .getSingle();
      expect(kolom.read<int>('nn'), 0);

      final e = await baru.select(baru.expenses).getSingle();
      expect(
        (e.shiftId, e.category, e.qty, e.amount),
        ('s-1', 'asset', 2, 5000),
      );

      await expectLater(
        baru.customStatement(
          "UPDATE expenses SET shift_id = 'tidak-ada' WHERE id = 'e-lama'",
        ),
        throwsA(anything),
        reason: 'foreign key ke shifts tetap berlaku',
      );
      await expectLater(
        baru.customStatement(
          "UPDATE expenses SET category = 'gaji' WHERE id = 'e-lama'",
        ),
        throwsA(anything),
        reason: 'pagar kategori ikut terbawa saat tabel dibangun ulang',
      );
    },
  );

  group('dialog Pengeluaran', () {
    test('galat isian', () {
      expect(
        galatFormPengeluaran(keterangan: ' ', nominalTeks: '5.000'),
        'Keterangan wajib diisi',
      );
      expect(
        galatFormPengeluaran(keterangan: 'Es', nominalTeks: ''),
        'Nominal wajib diisi',
      );
      expect(
        galatFormPengeluaran(keterangan: 'Es', nominalTeks: '5.000'),
        isNull,
      );
      expect(
        galatFormPengeluaran(
            keterangan: 'Es', nominalTeks: '5.000', jumlahTeks: ''),
        'Jumlah minimal 1',
      );
      expect(
        galatFormPengeluaran(
            keterangan: 'Es', nominalTeks: '5.000', jumlahTeks: '0'),
        'Jumlah minimal 1',
      );
    });

    testWidgets('total = nominal × jumlah, kategori terbawa', (t) async {
      InputPengeluaran? hasil;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => hasil = await tampilkanDialogPengeluaran(
                context,
                subjudul: 'Pengeluaran di luar shift',
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();

      await t.tap(find.text('Simpan'));
      await t.pump();
      expect(find.text('Keterangan wajib diisi'), findsOneWidget);

      await t.tap(find.text('Asset'));
      await t.enterText(find.byType(TextField).at(0), 'Beli Es Batu');
      await t.enterText(find.byType(TextField).at(1), '10000');
      await t.tap(find.bySemanticsLabel('Tambah jumlah'));
      await t.pump();
      await t.tap(find.text('Simpan'));
      await t.pumpAndSettle();

      expect(hasil!.keterangan, 'Beli Es Batu');
      expect(hasil!.qty, 2);
      expect(hasil!.amount, 20000);
      expect(hasil!.kategori.kode, 'asset');
    });

    testWidgets('"Rp" baru muncul saat Nominal diketuk, petunjuknya tetap',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => tampilkanDialogPengeluaran(
              context,
              subjudul: 'Pengeluaran di luar shift',
            ),
            child: const Text('buka'),
          ),
        ),
      ));
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();

      expect(find.text('Rp '), findsNothing,
          reason: 'belum diklik: tidak ada ruang "Rp" yang menggeser petunjuk');
      final xKeterangan = t.getTopLeft(find.text('Keterangan pengeluaran')).dx;
      final xNominal = t.getTopLeft(find.text('Nominal')).dx;
      expect(xNominal, moreOrLessEquals(xKeterangan, epsilon: 1),
          reason: 'petunjuk Nominal sejajar dengan Keterangan');

      await t.tap(find.byType(TextField).at(1));
      await t.pump();
      expect(find.text('Rp '), findsOneWidget);
      expect(find.text('Nominal'), findsOneWidget,
          reason: 'petunjuk tidak hilang saat Rp muncul');
    });

    testWidgets('jumlah bisa diketik langsung; panah tidak di bawah 1',
        (t) async {
      InputPengeluaran? hasil;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => hasil = await tampilkanDialogPengeluaran(
              context,
              subjudul: 'Pengeluaran di luar shift',
            ),
            child: const Text('buka'),
          ),
        ),
      ));
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();

      await t.tap(find.bySemanticsLabel('Kurangi jumlah'));
      await t.pump();
      expect(find.text('1'), findsOneWidget, reason: 'tidak turun di bawah 1');

      await t.enterText(find.byType(TextField).at(0), 'Gelas plastik');
      await t.enterText(find.byType(TextField).at(1), '500');
      await t.enterText(find.byKey(const Key('isian-jumlah')), '');
      await t.tap(find.text('Simpan'));
      await t.pump();
      expect(find.text('Jumlah minimal 1'), findsOneWidget);

      await t.enterText(find.byKey(const Key('isian-jumlah')), '12');
      await t.tap(find.bySemanticsLabel('Tambah jumlah'));
      await t.pump();
      await t.tap(find.text('Simpan'));
      await t.pumpAndSettle();
      expect(hasil!.qty, 13);
      expect(hasil!.amount, 6500);
    });
  });
}
