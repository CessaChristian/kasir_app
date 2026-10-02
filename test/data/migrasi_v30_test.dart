import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v30 SUNGGUHAN: transaksi mendapat kolom siapa yang
/// membatalkan dan alasannya. Transaksi lama — termasuk yang terhapus sebelum
/// fitur ini — tetap utuh, dengan kolom baru kosong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v30 menambah kolom pembatalan tanpa mengubah transaksi lama', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = Directory.systemTemp.createTempSync('uji_v30');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v29.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final dihapus = DateTime(2026, 9, 1);
    await lama.into(lama.transactions).insert(TransactionsCompanion.insert(
          id: const Value('t-lama'),
          total: 15000,
          paymentMethod: 'cash',
          deletedAt: Value(dihapus),
        ));
    await lama.close();

    // Keadaan v29: dua kolom itu belum ada.
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE transactions DROP COLUMN cancelled_by_user_id');
    mentah.execute('ALTER TABLE transactions DROP COLUMN cancel_reason');
    mentah.execute('PRAGMA user_version = 29');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    // Diperiksa langsung di skema: drift membaca dengan SELECT *, jadi kolom
    // yang TIDAK ADA terbaca null — sama persis dengan kolom yang ada tapi
    // kosong. Versi pertama test ini hanya memeriksa nilai null dan tetap
    // lulus walau migrasinya dimatikan.
    final kolom = (await baru
            .customSelect("SELECT name FROM pragma_table_info('transactions')")
            .get())
        .map((r) => r.read<String>('name'));
    final t = await baru.select(baru.transactions).getSingle();

    expect(kolom, containsAll(['cancelled_by_user_id', 'cancel_reason']));
    expect(t.total, 15000);
    expect(t.deletedAt, isNotNull,
        reason: 'yang terhapus sebelum fitur ini tetap tercatat dibatalkan');
    expect(t.cancelReason, isNull);

    // Dan kolomnya benar-benar bisa dipakai.
    await baru.into(baru.users).insert(UsersCompanion.insert(
          id: const Value('owner'),
          username: 'owner',
          pinHash: 'h',
          salt: 's',
          role: 'owner',
        ));
    await baru.into(baru.transactions).insert(TransactionsCompanion.insert(
          id: const Value('t-baru'),
          total: 5000,
          paymentMethod: 'cash',
        ));
    await baru.batalkanTransaksi('t-baru',
        olehUserId: 'owner', alasan: 'Salah input');
    final batal = await (baru.select(baru.transactions)
          ..where((x) => x.id.equals('t-baru')))
        .getSingle();
    await baru.close();
    expect(batal.cancelReason, 'Salah input');
  });
}
