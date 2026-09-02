import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/services/image_storage_service.dart';
import 'package:path/path.dart' as p;

/// Mengunci aturan penyimpanan gambar.
///
/// Latar belakang — gambar produk dulu disimpan apa adanya dari image_picker:
/// `/data/user/0/<paket>/cache/scaled_*.jpg`. Folder `cache` boleh dihapus
/// Android kapan saja saat penyimpanan menipis. Path-nya tetap tersimpan di
/// database, tapi filenya lenyap: produk tampil kosong dan tidak bisa
/// dipulihkan. Ini terjadi diam-diam — tidak ada error, tidak ada log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dasar;
  late ImageStorageService layanan;

  setUp(() {
    dasar = Directory.systemTemp.createTempSync('uji_gambar');
    ImageStorageService.folderDasar = dasar;
    layanan = ImageStorageService();
  });

  tearDown(() {
    ImageStorageService.folderDasar = null;
    if (dasar.existsSync()) dasar.deleteSync(recursive: true);
  });

  group('bentuk path', () {
    test('lokasiPenuhSync menggabungkan path relatif ke folder dokumen', () {
      final penuh = ImageStorageService.lokasiPenuhSync('products/abc.webp');
      expect(penuh, p.join(dasar.path, 'products', 'abc.webp'));
      expect(p.isAbsolute(penuh), isTrue);
    });

    test('path absolut peninggalan versi lama dikembalikan apa adanya', () {
      const lama = '/data/user/0/com.example.kasir_app/files/foto.jpg';
      expect(ImageStorageService.lokasiPenuhSync(lama), lama,
          reason: 'gambar lama harus tetap bisa ditampilkan');
    });

    test('adaSync false untuk null, kosong, dan file yang tidak ada', () {
      expect(ImageStorageService.adaSync(null), isFalse);
      expect(ImageStorageService.adaSync(''), isFalse);
      expect(ImageStorageService.adaSync('products/tidak-ada.webp'), isFalse);
    });
  });

  group('penyimpanan', () {
    test('hapus aman dipanggil untuk file yang sudah tidak ada', () async {
      await layanan.hapus('products/hantu.webp');
    });

    test('file yang benar-benar ada terdeteksi adaSync', () async {
      final folder = Directory(p.join(dasar.path, 'products'))
        ..createSync(recursive: true);
      File(p.join(folder.path, 'nyata.webp')).writeAsBytesSync([1, 2, 3]);

      expect(ImageStorageService.adaSync('products/nyata.webp'), isTrue);

      await layanan.hapus('products/nyata.webp');
      expect(ImageStorageService.adaSync('products/nyata.webp'), isFalse,
          reason: 'setelah dihapus tidak boleh terdeteksi lagi');
    });
  });

  group('sumber — cegah path cache masuk lagi', () {
    /// Pemakaian `picked.path` yang SAH: hanya sebagai sumber untuk disalin,
    /// bukan untuk disimpan ke database.
    test('tidak ada yang menyimpan picked.path langsung ke state/DB', () {
      final pelanggar = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;

        // Komentar dibuang dulu — dokumentasi di ImageStorageService sengaja
        // MENCONTOHKAN kode lama yang salah, dan itu bukan pelanggaran.
        final isi = entity
            .readAsStringSync()
            .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
        final path = entity.path.replaceAll(r'\', '/');

        // `_imagePath = picked.path` atau `imagePath: picked.path`
        final pola = RegExp(r'(?:_?imagePath\s*[=:]|imagePath:)\s*picked\.path');
        if (pola.hasMatch(isi)) pelanggar.add(path);

        // Kompresi di picker = lossy dua kali (JPEG lalu WebP).
        if (RegExp(r'pickImage\((?:[^)]*\n)*?[^)]*imageQuality:').hasMatch(isi)) {
          pelanggar.add('$path (imageQuality di pickImage)');
        }
      }

      expect(
        pelanggar,
        isEmpty,
        reason: 'Gambar dari image_picker berada di folder CACHE yang boleh '
            'dihapus Android kapan saja. Path-nya TIDAK boleh langsung masuk '
            'state atau database — salurkan lewat ImageStorageService.simpan() '
            'yang menyalinnya ke folder permanen dan mengembalikan path '
            'relatif. Jangan pula mengompres di pickImage: kompresi cukup '
            'sekali, di dalam service, langsung ke WebP.',
      );
    });
  });

  group('pembersihan file — mencegah sampah menumpuk', () {
    /// Bikin file gambar palsu, kembalikan path relatifnya.
    String buat(String nama) {
      final folder = Directory(p.join(dasar.path, 'products'))
        ..createSync(recursive: true);
      File(p.join(folder.path, nama)).writeAsBytesSync([1, 2, 3]);
      return 'products/$nama';
    }

    test('gambar yang diganti berkali-kali hanya menyisakan yang terakhir',
        () async {
      // Meniru user memilih foto tiga kali dalam satu sesi form.
      final a = buat('a.webp');
      final b = buat('b.webp');
      final c = buat('c.webp');

      // Yang dipertahankan hanya pilihan terakhir.
      for (final relatif in [a, b]) {
        await layanan.hapus(relatif);
      }

      expect(ImageStorageService.adaSync(a), isFalse);
      expect(ImageStorageService.adaSync(b), isFalse);
      expect(ImageStorageService.adaSync(c), isTrue,
          reason: 'pilihan terakhir harus tetap ada');
    });

    test('menghapus satu gambar tidak menyentuh gambar lain', () async {
      final lama = buat('lama.webp');
      final baru = buat('baru.webp');

      await layanan.hapus(lama);

      expect(ImageStorageService.adaSync(lama), isFalse);
      expect(ImageStorageService.adaSync(baru), isTrue,
          reason: 'penghapusan harus tepat sasaran, bukan mengosongkan folder');
    });

    test('hapus dua kali tidak melempar error', () async {
      final x = buat('x.webp');
      await layanan.hapus(x);
      await layanan.hapus(x);
      expect(ImageStorageService.adaSync(x), isFalse);
    });
  });

  group('sumber — pastikan hapus() benar-benar dipanggil', () {
    test('form membersihkan gambar yatim, products_page membuang yang lama',
        () {
      final form = File(
              'lib/features/products/sheets/product_form_sheet.dart')
          .readAsStringSync();
      expect(form.contains('_bersihkanGambarYatim'), isTrue,
          reason: 'form wajib membuang gambar yang tidak jadi dipakai');
      expect(form.contains('kecuali: _imagePath'), isTrue,
          reason: 'saat submit, pilihan akhir harus dikecualikan');

      final halaman =
          File('lib/features/products/pages/products_page.dart')
              .readAsStringSync();
      expect(halaman.contains('ImageStorageService().hapus('), isTrue,
          reason: 'gambar lama yang tergantikan wajib dibuang');
      // Penghapusan HARUS setelah upsertProduct, bukan sebelum: kalau
      // penyimpanan gagal, gambar lama tidak boleh sudah telanjur hilang.
      expect(
        halaman.indexOf('upsertProduct') <
            halaman.indexOf('ImageStorageService().hapus('),
        isTrue,
        reason: 'hapus gambar lama harus SETELAH penyimpanan berhasil',
      );
    });
  });
}
