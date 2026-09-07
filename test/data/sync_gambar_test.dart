import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_gambar.dart';
import 'package:kasir_app/shared/services/image_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mengunci aturan berkas gambar mana yang perlu berpindah.
///
/// Sinkronisasi tabel hanya memindahkan `products.image_path` — sebuah teks.
/// Berkasnya tidak ikut, sehingga perangkat kedua menerima baris yang menunjuk
/// `products/abc.webp` lalu mencarinya di disknya sendiri dan tidak
/// menemukannya. Produk tampil tanpa gambar, tanpa penjelasan apa pun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory folder;
  late ImageStorageService berkas;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    folder = await Directory.systemTemp.createTemp('uji_gambar');
    ImageStorageService.folderDasar = folder;
    berkas = ImageStorageService();
  });

  tearDown(() async {
    await db.close();
    ImageStorageService.folderDasar = null;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  Future<void> pasangProduk(String nama, String? gambar) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            name: nama,
            price: 5000,
            imagePath: Value(gambar),
          ));

  test('path yang dirujuk baris produk terkumpul semua', () async {
    await pasangProduk('Kopi', 'products/a.webp');
    await pasangProduk('Teh', 'products/b.webp');
    await pasangProduk('Air', null);

    final mesin = SyncGambar(db, _KlienPalsu(), berkas: berkas);

    expect(await mesin.pathDirujuk(), {'products/a.webp', 'products/b.webp'},
        reason: 'produk tanpa gambar tidak boleh ikut');
  });

  test('produk yang sudah dihapus lunak TETAP dihitung', () async {
    // Berkasnya masih dibutuhkan: riwayat transaksi lama menampilkan
    // produknya, dan penghapusan lunak bisa dibatalkan. Berkas baru boleh
    // dianggap tidak terpakai kalau TIDAK ADA baris sama sekali yang
    // menunjuknya.
    await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Kopi Lama',
          price: 5000,
          imagePath: const Value('products/lama.webp'),
          deletedAt: Value(DateTime.now()),
        ));

    final mesin = SyncGambar(db, _KlienPalsu(), berkas: berkas);

    expect(await mesin.pathDirujuk(), {'products/lama.webp'});
  });

  test('simpanBytes membuat foldernya kalau belum ada', () async {
    // Perangkat yang belum pernah menyimpan gambar sendiri belum punya folder
    // `products/`. Tanpa membuatnya, unduhan pertama gagal.
    expect(Directory('${folder.path}/products').existsSync(), isFalse);

    await berkas.simpanBytes('products/baru.webp', Uint8List.fromList([1, 2, 3]));

    expect(await berkas.ada('products/baru.webp'), isTrue);
    expect(
      File('${folder.path}/products/baru.webp').readAsBytesSync(),
      [1, 2, 3],
    );
  });

  test('ada() membedakan berkas yang benar-benar ada', () async {
    expect(await berkas.ada('products/hantu.webp'), isFalse);
    await berkas.simpanBytes('products/nyata.webp', Uint8List.fromList([9]));
    expect(await berkas.ada('products/nyata.webp'), isTrue);
  });

  test('path kosong tidak dianggap rujukan', () async {
    await pasangProduk('Aneh', '');
    final mesin = SyncGambar(db, _KlienPalsu(), berkas: berkas);
    expect(await mesin.pathDirujuk(), isEmpty);
  });
}

/// Cukup untuk membangun SyncGambar. Setiap panggilan ke jaringan MELEMPAR —
/// itu disengaja: test di berkas ini menguji keputusan berkas mana yang perlu
/// berpindah, dan tidak satu pun boleh diam-diam menghubungi server.
class _KlienPalsu implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
      'test ini tidak boleh menyentuh jaringan: ${i.memberName}');
}
