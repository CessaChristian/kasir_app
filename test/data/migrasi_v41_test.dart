import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v41 (revisi QA C3a + C4): indeks database HP, dan penanda tarik
/// dikosongkan supaya kolom v36–v39 terisi dari server untuk baris lama.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> daftarIndeks(AppDatabase db) async => [
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name LIKE 'idx_%' ORDER BY name",
            )
            .get())
      r.read<String>('name'),
  ];

  test(
    'migrasi v40 → v41: indeks dipasang, penanda tarik kosong, data utuh',
    () async {
      final folder = Directory.systemTemp.createTempSync('uji_v41');
      addTearDown(() => folder.deleteSync(recursive: true));
      final jalur = '${folder.path}/v40.sqlite';

      final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      await lama
          .into(lama.products)
          .insert(
            ProductsCompanion.insert(
              id: const Value('p-1'),
              name: 'Kopi',
              price: 10000,
            ),
          );
      await lama
          .into(lama.syncState)
          .insert(
            SyncStateCompanion.insert(
              entity: 'users',
              lastPulledCursor: const Value('2026-10-20T10:00:00+00:00'),
            ),
          );
      await lama.close();

      // Keadaan HP yang masih v40: belum ada indeks satu pun.
      final mentah = sqlite3.open(jalur);
      for (final r in mentah.select(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name LIKE 'idx_%'",
      )) {
        mentah.execute('DROP INDEX ${r['name']}');
      }
      mentah.execute('PRAGMA user_version = 40');
      mentah.dispose();

      final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      addTearDown(baru.close);
      expect((await baru.select(baru.products).get()).single.name, 'Kopi');
      expect(await daftarIndeks(baru), hasLength(18));
      final penanda = await baru.select(baru.syncState).getSingle();
      expect(
        penanda.lastPulledCursor,
        isNull,
        reason: 'tarik ulang dari awal supaya nomor_kasir dkk. terisi',
      );
    },
  );

  test('database baru langsung punya indeks yang sama', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await daftarIndeks(db), hasLength(18));
  });

  test('SQLite benar-benar memakai indeksnya', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    Future<String> rencana(String sql) async => [
      for (final r in await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
        r.read<String>('detail'),
    ].join(' | ');

    expect(
      await rencana(
        "SELECT * FROM transaction_items WHERE transaction_id = 'x'",
      ),
      contains('idx_item_tx'),
    );
    expect(
      await rencana('SELECT * FROM transactions WHERE created_at >= 1'),
      contains('idx_tx_dibuat'),
    );
    expect(
      await rencana("SELECT * FROM expenses WHERE sync_status = 'pending'"),
      contains('idx_expenses_pending'),
    );
  });
}
