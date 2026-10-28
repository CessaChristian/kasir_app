import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Baris yang diubah di server SELAGI ditarik pindah ke belakang urutan dan
/// datang dua kali (revisi QA C3c). Dulu id semua baris disimpan di memori
/// untuk membuang salinan kedua — HP baru menampung ratusan ribu id, dan
/// justru versi terbaru yang dibuang sampai sinkron berikutnya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Map<String, dynamic> kategori(String id, String nama, DateTime waktu) {
    final w = waktu.toUtc().toIso8601String();
    return {
      'id': id,
      'name': nama,
      'icon_codepoint': null,
      'tampil_di_kasir': true,
      'created_at': w,
      'updated_at': w,
      'deleted_at': null,
      'server_urut': w,
    };
  }

  test('salinan kedua yang lebih baru ikut tersimpan', () async {
    final awal = DateTime.utc(2026, 10, 28, 10);
    final halaman1 = [
      for (var i = 0; i < SyncEngine.ukuranHalaman; i++)
        kategori(
          'k-${i.toString().padLeft(4, '0')}',
          i == 10 ? 'Lama' : 'Kategori $i',
          awal.add(Duration(seconds: i)),
        ),
    ];
    // k-0010 diubah di server sesudah halaman pertama terkirim.
    final halaman2 = [
      kategori('k-0010', 'Baru', awal.add(const Duration(hours: 1))),
    ];
    var panggilan = 0;
    final mesin = SyncEngine(db)
      ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
        if (tabel != 'categories') return const [];
        panggilan++;
        return switch (panggilan) {
          1 => halaman1,
          2 => halaman2,
          _ => const [],
        };
      };

    await mesin.tarikTabel('categories');
    final k = await (db.select(
      db.categories,
    )..where((c) => c.id.equals('k-0010'))).getSingle();
    expect(k.name, 'Baru');
    expect(await db.select(db.categories).get(), hasLength(500));
  });
}
