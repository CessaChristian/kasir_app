import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v25 SUNGGUHAN di atas database berversi 24.
///
/// Tarikan sebelum v25 melewatkan baris secara permanen (urutan turun +
/// penanda cap saja), dan penanda yang tersimpan sudah melompat melewati
/// baris-baris itu. Kalau penandanya tidak dikosongkan, perbaikan di
/// `SyncEngine` tidak menolong HP yang sudah terpasang: ia hanya menarik
/// yang BARU, dan yang bolong tetap bolong selamanya.
///
/// Skema v24 dan v25 sama persis, jadi database v24 cukup dibuat dari
/// database terbaru yang nomor versinya diturunkan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late String jalur;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('uji_v25');
    jalur = '${folder.path}/v24.sqlite';
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test('v25 mengosongkan penanda tarikan supaya yang bolong ikut terisi',
      () async {
    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.syncState).insert(SyncStateCompanion.insert(
          entity: 'transaction_items',
          lastPulledCursor: const Value('2026-10-01T10:47:46.93446+00:00'),
        ));
    await lama.close();

    final mentah = sqlite3.open(jalur);
    mentah.execute('PRAGMA user_version = 24');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final penanda = await baru.select(baru.syncState).get();
    await baru.close();

    expect(penanda, hasLength(1), reason: 'barisnya tetap, isinya saja kosong');
    expect(penanda.single.lastPulledCursor, isNull);
  });
}
