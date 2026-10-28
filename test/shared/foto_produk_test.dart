import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kasir_app/data/sync/sync_gambar.dart';
import 'package:kasir_app/features/products/sheets/product_form_sheet.dart';
import 'package:kasir_app/shared/services/image_storage_service.dart';
import 'package:path/path.dart' as p;

/// Foto produk: kompres gagal, izin ditolak, dan satu foto bermasalah saat
/// sinkron.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dasar;
  late File sumber;

  setUp(() {
    dasar = Directory.systemTemp.createTempSync('uji_foto');
    ImageStorageService.folderDasar = dasar;
    sumber = File(p.join(dasar.path, 'asli.heic'))
      ..writeAsBytesSync(List.filled(5 * 1024 * 1024, 7));
  });
  tearDown(() {
    ImageStorageService.folderDasar = null;
    if (dasar.existsSync()) dasar.deleteSync(recursive: true);
  });

  /// Pengompres palsu: format di [berhasil] menulis berkas kecil, format
  /// di [melempar] melempar galat, sisanya mengembalikan null.
  Pengompres palsu({
    Set<CompressFormat> berhasil = const {},
    Set<CompressFormat> melempar = const {},
  }) => (asal, tujuan, format) async {
    if (melempar.contains(format)) throw Exception('encoder rusak');
    if (!berhasil.contains(format)) return null;
    File(tujuan).writeAsBytesSync([1, 2, 3]);
    return XFile(tujuan);
  };

  List<String> isiFolder() => [
    for (final f in Directory(
      p.join(dasar.path, ImageStorageService.folderProduk),
    ).listSync())
      p.basename(f.path),
  ];

  group('kompres', () {
    test('WebP berhasil: disimpan .webp', () async {
      final hasil = await ImageStorageService(
        kompres: palsu(berhasil: {CompressFormat.webp}),
      ).simpan(sumber);
      expect(hasil, endsWith('.webp'));
    });

    test('WebP gagal (null atau galat): jatuh ke JPEG', () async {
      for (final layanan in [
        ImageStorageService(kompres: palsu(berhasil: {CompressFormat.jpeg})),
        ImageStorageService(
          kompres: palsu(
            berhasil: {CompressFormat.jpeg},
            melempar: {CompressFormat.webp},
          ),
        ),
      ]) {
        expect(await layanan.simpan(sumber), endsWith('.jpg'));
      }
    });

    test(
      'semua gagal: ditolak dengan pesan, foto ASLI tidak disalin',
      () async {
        // Dulu foto asli (bisa beberapa MB) disalin apa adanya, ditolak
        // server karena kebesaran, dan menahan antrean unggah foto.
        await expectLater(
          ImageStorageService(kompres: palsu()).simpan(sumber),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'pesan',
              ImageStorageService.pesanFotoGagal,
            ),
          ),
        );
        expect(isiFolder(), isEmpty);
      },
    );
  });

  group('izin', () {
    test('izin ditolak: pesan menyebut kamera/galeri dan Pengaturan', () {
      expect(
        pesanIzinFoto(
          PlatformException(code: 'camera_access_denied'),
          ImageSource.camera,
        ),
        'Izin kamera ditolak. Buka Pengaturan HP untuk mengizinkan.',
      );
      expect(
        pesanIzinFoto(
          PlatformException(code: 'photo_access_denied'),
          ImageSource.gallery,
        ),
        'Izin galeri ditolak. Buka Pengaturan HP untuk mengizinkan.',
      );
      expect(
        pesanIzinFoto(PlatformException(code: 'lain'), ImageSource.gallery),
        'Tidak bisa membuka galeri. Coba lagi.',
      );
    });
  });

  group('sinkron per berkas', () {
    test('satu berkas gagal tidak menghentikan yang lain', () async {
      final dikerjakan = <String>[];
      final gagal = <String>[];
      var maju = 0;
      final berhasil = await kerjakanPerBerkas(
        ['a.webp', 'rusak.heic', 'c.webp'],
        gagal,
        (path) async {
          if (path == 'rusak.heic') throw Exception('Payload too large');
          dikerjakan.add(path);
        },
        () => maju++,
      );
      expect(berhasil, 2);
      expect(dikerjakan, ['a.webp', 'c.webp']);
      expect(gagal.single, startsWith('rusak.heic'));
      expect(maju, 3);
    });
  });
}
