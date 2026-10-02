import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/sales/models/pilihan_produk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Pilihan produk — Pedas, Manis, Es.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Product produk({bool pedas = false, bool manis = false, bool es = false}) =>
      Product(
        id: 'p',
        name: 'Es Teh',
        price: 5000,
        hasSpicyOption: pedas,
        hasSweetOption: manis,
        hasIceOption: es,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        syncStatus: 'synced',
      );

  test('isi dan pilihan bawaan tiap kelompok sesuai kesepakatan', () {
    expect(KelompokPilihan.pedas.daftar,
        ['Tidak Pedas', 'Sedang', 'Pedas', 'Ekstra Pedas']);
    expect(KelompokPilihan.manis.daftar,
        ['Tanpa Gula', 'Sedikit', 'Normal', 'Ekstra Gula']);
    expect(KelompokPilihan.es.daftar,
        ['Tanpa Es', 'Sedikit', 'Normal', 'Ekstra Es']);
    expect(
        [for (final k in KelompokPilihan.values) k.bawaan],
        ['Tidak Pedas', 'Normal', 'Normal']);
    for (final k in KelompokPilihan.values) {
      expect(k.daftar, contains(k.bawaan));
    }
  });

  test('hanya kelompok yang dinyalakan di produk yang ditanyakan', () {
    expect(kelompokUntuk(produk()), isEmpty);
    expect(kelompokUntuk(produk(manis: true, es: true)),
        [KelompokPilihan.manis, KelompokPilihan.es]);
  });

  test('catatan menyebut nama kelompok dan urutannya selalu tetap', () {
    // Keranjang menggabungkan baris berdasarkan catatan ini, jadi pilihan
    // yang sama wajib menghasilkan teks yang sama persis — apa pun urutan
    // kasir mengetuknya.
    final a = catatanDari({
      KelompokPilihan.es: 'Normal',
      KelompokPilihan.manis: 'Sedikit',
    });
    final b = catatanDari({
      KelompokPilihan.manis: 'Sedikit',
      KelompokPilihan.es: 'Normal',
    });
    expect(a, 'Manis: Sedikit · Es: Normal');
    expect(a, b);
  });

  test('migrasi v28 menambah kolom Manis dan Es tanpa mengubah produk lama',
      () async {
    SharedPreferences.setMockInitialValues({});
    final folder = Directory.systemTemp.createTempSync('uji_v28');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v27.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.products).insert(ProductsCompanion.insert(
          id: const Value('p-mie'),
          name: 'Mie Goreng',
          price: 16000,
          hasSpicyOption: const Value(true),
        ));
    await lama.close();

    // Keadaan v27: dua kolom itu belum ada.
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE products DROP COLUMN has_sweet_option');
    mentah.execute('ALTER TABLE products DROP COLUMN has_ice_option');
    mentah.execute('PRAGMA user_version = 27');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final p = await baru.select(baru.products).getSingle();
    await baru.close();

    expect(p.hasSpicyOption, isTrue, reason: 'pilihan pedas lama tetap');
    expect(p.hasSweetOption, isFalse);
    expect(p.hasIceOption, isFalse);
  });

  test('server yang belum punya kolom baru tidak membuat sinkron gagal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Baris dari server SEBELUM supabase/produk_pilihan.sql dijalankan.
    final hasil = await SyncEngine(db).gabungkanTabel('products', [
      {
        'id': 'p-lama',
        'name': 'Kopi',
        'price': 8000,
        'barcode': null,
        'category_id': null,
        'has_spicy_option': false,
        'image_path': null,
        'created_at': '2026-09-01T00:00:00+00:00',
        'updated_at': '2026-09-01T00:00:00+00:00',
        'deleted_at': null,
        'server_urut': '2026-09-01T00:00:00+00:00',
      },
    ]);

    expect(hasil, (1, 1));
    final p = await db.select(db.products).getSingle();
    expect(p.hasSweetOption, isFalse);
    expect(p.hasIceOption, isFalse);
  });
}
