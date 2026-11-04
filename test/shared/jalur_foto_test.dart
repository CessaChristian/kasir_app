import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/services/image_storage_service.dart';
import 'package:path/path.dart' as p;

/// `products.image_path` datang dari server, jadi tidak boleh dipercaya:
/// nilai `kasir_app.sqlite` dulu bisa menghapus database HP saat fotonya
/// diganti, dan bisa mengunggah database itu ke Storage (audit nomor 9).
void main() {
  late Directory dasar;
  late File database;
  final layanan = ImageStorageService();

  const jahat = [
    'kasir_app.sqlite',
    '../kasir_app.sqlite',
    'products/../kasir_app.sqlite',
    'products/x.sqlite',
    'products/sub/x.webp',
    '/data/user/0/id.terasinn.kasir/app_flutter/kasir_app.sqlite',
    'lain/x.webp',
    'products/.webp',
    '',
  ];

  setUp(() {
    dasar = Directory.systemTemp.createTempSync('uji_jalur');
    ImageStorageService.folderDasar = dasar;
    database = File(p.join(dasar.path, 'kasir_app.sqlite'))
      ..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() {
    ImageStorageService.folderDasar = null;
    dasar.deleteSync(recursive: true);
  });

  test('hanya berkas foto di dalam products/ yang sah', () {
    expect(
      ImageStorageService.jalurSah(
        'products/0b9d6c1e-6c55-4b7e-9a51-2f7a1f0c1a11.webp',
      ),
      isTrue,
    );
    expect(ImageStorageService.jalurSah('products/lama.jpg'), isTrue);
    expect(ImageStorageService.jalurSah(null), isFalse);
    for (final j in jahat) {
      expect(ImageStorageService.jalurSah(j), isFalse, reason: j);
    }
  });

  test('jalur jahat tidak bisa menghapus database', () async {
    for (final j in jahat) {
      await layanan.hapus(j);
      expect(database.existsSync(), isTrue, reason: j);
    }
  });

  test('jalur jahat dianggap tidak ada, jadi tidak ikut diunggah', () async {
    for (final j in ['kasir_app.sqlite', database.path]) {
      expect(await layanan.ada(j), isFalse, reason: j);
      expect(ImageStorageService.adaSync(j), isFalse, reason: j);
      await expectLater(layanan.fileDari(j), throwsStateError, reason: j);
    }
  });

  test('jalur jahat tidak bisa menimpa database lewat unduhan', () async {
    await expectLater(
      layanan.simpanBytes('kasir_app.sqlite', Uint8List.fromList([9])),
      throwsStateError,
    );
    expect(database.readAsBytesSync(), [1, 2, 3]);
  });
}
