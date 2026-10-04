import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v32: pengeluaran mendapat kategori biaya (wajib, tiga pilihan) dan
/// jumlah (desain baru).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> isiAwal(AppDatabase db) async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'budi'));
  }

  test('migrasi v31 → v32: category & qty ditambah, data lama jadi Bahan Baku',
      () async {
    final folder = Directory.systemTemp.createTempSync('uji_v32');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v31.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await isiAwal(lama);
    await lama.into(lama.expenses).insert(ExpensesCompanion.insert(
          id: const Value('e-lama'),
          shiftId: const Value('s-1'),
          userId: 'budi',
          description: 'Es batu',
          amount: 5000,
        ));
    await lama.close();

    // Keadaan v31: kedua kolom belum ada.
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE expenses DROP COLUMN category');
    mentah.execute('ALTER TABLE expenses DROP COLUMN qty');
    mentah.execute('PRAGMA user_version = 31');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baru.close);
    final kolom = (await baru
            .customSelect("SELECT name FROM pragma_table_info('expenses')")
            .get())
        .map((r) => r.read<String>('name'))
        .toList();
    expect(kolom, containsAll(['category', 'qty']));

    final e = await baru.select(baru.expenses).getSingle();
    expect(e.amount, 5000);
    expect(e.category, 'bahan_baku',
        reason: 'tidak ada "Lainnya" — data lama masuk Bahan Baku');
    expect(e.qty, 1);

    // Kolom hasil migrasi juga terpagar (ALTER TABLE membawa CHECK-nya).
    await expectLater(
        baru.customStatement(
            "UPDATE expenses SET category = 'ngawur' WHERE id = 'e-lama'"),
        throwsA(anything));
    await expectLater(
        baru.customStatement("UPDATE expenses SET qty = 0 WHERE id = 'e-lama'"),
        throwsA(anything));
    await expectLater(
        baru.customStatement(
            "UPDATE expenses SET category = NULL WHERE id = 'e-lama'"),
        throwsA(anything),
        reason: 'kategori wajib diisi');
  });

  group('basis data baru', () {
    late AppDatabase db;
    late ExpenseRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ExpenseRepository(db);
      await isiAwal(db);
    });
    tearDown(() => db.close());

    test('form kasir menyimpan kategori, jumlah, dan TOTAL di amount',
        () async {
      await repo.addExpense(
        shiftId: 's-1',
        userId: 'budi',
        description: 'Beli Es Batu',
        amount: 20000,
        category: 'bahan_baku',
        qty: 2,
      );
      final e = await db.select(db.expenses).getSingle();
      expect(e.category, 'bahan_baku');
      expect(e.qty, 2);
      expect(e.amount, 20000);
      expect(e.syncStatus, 'pending');
    });

    test('kategori tak dikenal ditolak database', () async {
      await expectLater(
        repo.addExpense(
            shiftId: 's-1',
            userId: 'budi',
            description: 'x',
            amount: 1,
            category: 'gaji'),
        throwsA(anything),
      );
    });

    test('kueri periode: batas tanggal inklusif, yang dibatalkan ikut',
        () async {
      Future<void> catat(String id, DateTime waktu, {bool batal = false}) =>
          db.into(db.expenses).insert(ExpensesCompanion.insert(
                id: Value(id),
                shiftId: const Value('s-1'),
                userId: 'budi',
                description: id,
                amount: 1000,
                createdAt: Value(waktu),
                deletedAt: Value(batal ? waktu : null),
              ));
      await catat('sebelum', DateTime(2026, 9, 30, 23, 59));
      await catat('awal', DateTime(2026, 10, 1, 0, 0));
      await catat('batal', DateTime(2026, 10, 2, 12), batal: true);
      await catat('akhir', DateTime(2026, 10, 3, 23, 59));
      await catat('sesudah', DateTime(2026, 10, 4, 0, 0));

      final isi = await repo
          .watchPengeluaranPeriode(
              Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 3)))
          .first;
      expect(isi.map((e) => e.id), ['akhir', 'batal', 'awal']);
    });
  });
}
