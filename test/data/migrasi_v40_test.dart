import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v40: tabel lokal `baris_tertahan` untuk baris server yang ditolak
/// database HP saat ditarik.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('migrasi v39 → v40: tabel baris_tertahan dibuat, data lama utuh',
      () async {
    final folder = Directory.systemTemp.createTempSync('uji_v40');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v39.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.products).insert(ProductsCompanion.insert(
          id: const Value('p-1'),
          name: 'Kopi',
          price: 10000,
        ));
    await lama.close();

    // Keadaan HP yang masih v39: tabelnya belum ada.
    final mentah = sqlite3.open(jalur);
    mentah.execute('DROP TABLE baris_tertahan');
    mentah.execute('PRAGMA user_version = 39');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baru.close);
    expect((await baru.select(baru.products).get()).single.name, 'Kopi');
    await baru.into(baru.barisTertahan).insert(BarisTertahanCompanion.insert(
          entity: 'expenses',
          rowId: 'e-1',
          alasan: 'CHECK constraint failed',
        ));
    expect(await baru.jumlahTertahan(), 1);
  });
}
