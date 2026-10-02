import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v31 SUNGGUHAN: pengeluaran mendapat kolom
/// pembatalan, dan `updated_by_user_id` (siapa yang terakhir mengedit atau
/// menghapus) dicopot karena fitur edit sudah dibuang.
///
/// Diperiksa langsung di skema: drift membaca dengan SELECT *, jadi kolom yang
/// tidak ada terbaca sama dengan kolom yang kosong (pelajaran dari v30).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v31 menambah kolom pembatalan dan mencopot updated_by_user_id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final folder = Directory.systemTemp.createTempSync('uji_v31');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v30.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.users).insert(UsersCompanion.insert(
          id: const Value('budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await lama.into(lama.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'budi'));
    await lama.into(lama.expenses).insert(ExpensesCompanion.insert(
          id: const Value('e-1'),
          shiftId: 's-1',
          userId: 'budi',
          description: 'Es batu',
          amount: 5000,
        ));
    await lama.close();

    // Keadaan v30: kolom pembatalan belum ada, updated_by_user_id masih ada.
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE expenses DROP COLUMN cancelled_by_user_id');
    mentah.execute('ALTER TABLE expenses DROP COLUMN cancel_reason');
    mentah.execute(
        'ALTER TABLE expenses ADD COLUMN updated_by_user_id TEXT NULL '
        'REFERENCES users (id)');
    mentah.execute("UPDATE expenses SET updated_by_user_id = 'budi'");
    mentah.execute('PRAGMA user_version = 30');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final kolom = (await baru
            .customSelect("SELECT name FROM pragma_table_info('expenses')")
            .get())
        .map((r) => r.read<String>('name'))
        .toList();
    final e = await baru.select(baru.expenses).getSingle();
    await baru.batalkanPengeluaran('e-1',
        olehUserId: 'budi', alasan: 'Salah input');
    final batal = await baru.select(baru.expenses).getSingle();
    await baru.close();

    expect(kolom, containsAll(['cancelled_by_user_id', 'cancel_reason']));
    expect(kolom, isNot(contains('updated_by_user_id')));
    expect(e.amount, 5000, reason: 'isi pengeluaran lama tidak tersentuh');
    expect(batal.cancelReason, 'Salah input');
  });
}
