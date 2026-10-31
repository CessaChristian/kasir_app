import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/data/sync/sync_otomatis.dart';
import 'package:kasir_app/data/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Review R1 — sinkron tidak boleh mengulang dirinya tanpa henti.
///
/// Aturan K10 mengulang sinkron sekali kalau masih ada yang tertunda selain
/// baris yang DITOLAK server. Tabel yang gagal karena galat lain (mis. isi
/// open bill rusak, jadi tidak bisa dibaca untuk dikirim) tidak masuk
/// hitungan "ditolak", jadi barisnya terus dianggap data baru dan sinkron
/// diulang tiap putaran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('tabel yang gagal dibaca: jumlah ditolak tidak diketahui, '
      'sinkron TIDAK diulang', () async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
      "INSERT INTO open_bills (id, name, shift_id, user_id, items, "
      "created_at, updated_at, sync_status) "
      "VALUES ('b-1', 'Meja 1', 's-1', 'u-1', 'bukan json', 0, 0, 'pending')",
    );
    final mesin = SyncEngine(db)..pengirimUntukTest = (_, _) async {};
    final (_, gagal) = await mesin.dorongSemua();
    expect(gagal.single, startsWith('open_bills'));
    expect(mesin.ditolak, isNull, reason: 'ada tabel yang tidak terkirim');

    final h = HasilSync(
      error: gagal.single,
      tarikSelesai: true,
      ditolak: mesin.ditolak,
    );
    expect(SyncService.perluUlang(h, await db.jumlahTertunda()), isFalse);
  });

  test('tulisan hasil tarikan server tidak memicu sinkron lagi; '
      'perubahan pemakai tetap memicu', () async {
    final w = DateTime.utc(2026, 10, 31, 10).toIso8601String();
    final mesin = SyncEngine(db)
      ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
          tabel == 'categories' && setelah == null
              ? [
                  {
                    'id': 'k-1',
                    'name': 'Minuman',
                    'icon_codepoint': null,
                    'tampil_di_kasir': true,
                    'created_at': w,
                    'updated_at': w,
                    'deleted_at': null,
                    'server_urut': w,
                  },
                ]
              : const [];
    // Ditarik dua kali: penanda `gte` membawa barisnya lagi dan menulisnya.
    await mesin.tarikTabel('categories');
    await mesin.tarikTabel('categories');

    final s = SyncOtomatis.instance..resetUntukTest();
    addTearDown(s.resetUntukTest);
    // Keranjang berisi: kalau sampai dipicu, sinkronnya hanya ditunda —
    // tidak menyentuh jaringan.
    s.sedangMenyusunPesanan = true;
    expect(await s.kirimKalauAdaTertunda(hitungTertunda: db.jumlahTertunda),
        isFalse);

    await (db.update(db.categories)..where((c) => c.id.equals('k-1')))
        .write(const CategoriesCompanion(syncStatus: Value('pending')));
    expect(await s.kirimKalauAdaTertunda(hitungTertunda: db.jumlahTertunda),
        isTrue);
  });
}
