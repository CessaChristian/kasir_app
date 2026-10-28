import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/uuid_helper.dart';

/// Satu-satunya pintu penyimpanan gambar aplikasi.
///
/// Sebelum ini, gambar produk disimpan apa adanya dari `image_picker`:
///
/// ```dart
/// setState(() => _imagePath = picked.path);   // /data/.../cache/scaled_*.jpg
/// ```
///
/// Path itu menunjuk folder **cache**, yang boleh dihapus Android kapan saja
/// saat penyimpanan menipis — tanpa memberi tahu aplikasi. Path-nya tetap
/// tersimpan di database, tapi filenya lenyap dan tidak bisa dipulihkan.
///
/// Dua aturan yang dijaga kelas ini:
///
/// 1. **File disalin ke folder permanen.** `getApplicationDocumentsDirectory`
///    tidak pernah dibersihkan sistem.
/// 2. **Database menyimpan path RELATIF** (`products/<uuid>.webp`), bukan
///    absolut. Path absolut memuat lokasi instalasi: di Android relatif
///    stabil, tapi di iOS berubah setiap kali aplikasi di-update sehingga
///    seluruh gambar "hilang" sekaligus. Bentuk relatif juga yang nanti
///    dipakai Supabase Storage, jadi tidak perlu diubah dua kali.
/// Mengompres [sumber] ke [tujuan]. Null = gagal. Bisa diganti di test.
typedef Pengompres =
    Future<XFile?> Function(String sumber, String tujuan, CompressFormat format);

class ImageStorageService {
  ImageStorageService({Pengompres? kompres})
    : _kompres = kompres ?? _kompresAsli;

  final Pengompres _kompres;

  static Future<XFile?> _kompresAsli(
    String sumber,
    String tujuan,
    CompressFormat format,
  ) => FlutterImageCompress.compressAndGetFile(
    sumber,
    tujuan,
    format: format,
    minWidth: _sisiMaksimal,
    minHeight: _sisiMaksimal,
    quality: _kualitas,
  );

  /// Pesan kalau foto tidak bisa dikompres sama sekali.
  static const pesanFotoGagal = 'Foto ini tidak bisa dipakai. Pilih foto lain.';

  /// Sisi terpanjang gambar setelah dikompres.
  static const int _sisiMaksimal = 800;

  /// 0-100. Di WebP, 80 sudah sulit dibedakan dari aslinya.
  static const int _kualitas = 80;

  /// Subfolder gambar produk, relatif terhadap folder dokumen aplikasi.
  static const String folderProduk = 'products';

  /// Folder dokumen aplikasi, di-cache sekali lewat [init].
  ///
  /// Perlu di-cache karena `build()` widget tidak bisa menunggu Future —
  /// tanpa ini setiap penggambaran gambar harus lewat FutureBuilder.
  /// Test boleh mengisinya langsung supaya tidak menyentuh path_provider.
  static Directory? folderDasar;

  /// Panggil sekali di `main()` sebelum `runApp`.
  static Future<void> init() async {
    folderDasar ??= await getApplicationDocumentsDirectory();
  }

  Future<Directory> _folderDasar() async {
    await init();
    return folderDasar!;
  }

  /// Ubah path relatif dari database jadi path absolut yang bisa dibuka.
  ///
  /// Path absolut peninggalan versi lama dikembalikan apa adanya, supaya
  /// gambar yang terlanjur tersimpan tetap tampil.
  ///
  /// Versi SINKRON — dipakai di `build()`. Mengembalikan string kosong kalau
  /// [init] belum dipanggil, sehingga pemanggil cukup memeriksa file-nya ada
  /// atau tidak seperti biasa.
  static String lokasiPenuhSync(String relatif) {
    if (p.isAbsolute(relatif)) return relatif;
    final dasar = folderDasar;
    if (dasar == null) return '';
    return p.join(dasar.path, relatif);
  }

  /// Apakah file gambarnya ada — versi sinkron untuk `build()`.
  static bool adaSync(String? relatif) {
    if (relatif == null || relatif.isEmpty) return false;
    final penuh = lokasiPenuhSync(relatif);
    return penuh.isNotEmpty && File(penuh).existsSync();
  }

  Future<String> lokasiPenuh(String relatif) async {
    if (p.isAbsolute(relatif)) return relatif;
    final dasar = await _folderDasar();
    return p.join(dasar.path, relatif);
  }

  /// Simpan gambar dari [sumber] sebagai WebP (JPEG kalau encoder WebP
  /// gagal) di folder permanen. Melempar [StateError] berisi
  /// [pesanFotoGagal] kalau keduanya gagal.
  ///
  /// Mengembalikan path RELATIF untuk disimpan ke database.
  ///
  /// [sumber] diharapkan gambar ASLI dari picker — jangan dikompres dulu di
  /// sana. Mengompres dua kali (JPEG lalu WebP) menurunkan kualitas dua
  /// tahap tanpa memperkecil ukuran secara sebanding.
  Future<String> simpan(File sumber, {String subfolder = folderProduk}) async {
    final dasar = await _folderDasar();
    final tujuanFolder = Directory(p.join(dasar.path, subfolder));
    if (!tujuanFolder.existsSync()) {
      tujuanFolder.createSync(recursive: true);
    }

    // WebP dulu; kalau encoder-nya gagal, JPEG. Foto ASLI tidak pernah
    // disalin lagi: ukurannya bisa beberapa MB, ditolak server, dan dulu
    // membuat antrean unggah foto macet.
    for (final (format, ekstensi) in const [
      (CompressFormat.webp, 'webp'),
      (CompressFormat.jpeg, 'jpg'),
    ]) {
      final tujuan = p.join(tujuanFolder.path, '${newUuid()}.$ekstensi');
      try {
        final hasil = await _kompres(sumber.absolute.path, tujuan, format);
        if (hasil != null) return p.join(subfolder, p.basename(hasil.path));
      } catch (_) {
        // Coba format berikutnya.
      }
    }
    throw StateError(pesanFotoGagal);
  }

  /// Objek [File] untuk path relatif, untuk diserahkan ke pengunggah.
  Future<File> fileDari(String relatif) async => File(await lokasiPenuh(relatif));

  /// Tulis gambar yang diunduh dari server ke lokasinya di [relatif].
  ///
  /// Dipakai sinkronisasi gambar: barisnya sudah sampai lebih dulu lewat sync
  /// tabel, dan berkasnya menyusul. Foldernya dibuat kalau belum ada, karena
  /// perangkat yang belum pernah menyimpan gambar sendiri belum punya
  /// `products/`.
  Future<void> simpanBytes(String relatif, Uint8List data) async {
    final penuh = await lokasiPenuh(relatif);
    final file = File(penuh);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
  }

  /// Semua berkas gambar yang ada di disk, sebagai path RELATIF.
  ///
  /// Bentuknya sengaja sama dengan isi `products.image_path`, supaya bisa
  /// langsung dibandingkan tanpa perlu menyusun ulang prefiks di pemanggil.
  /// Folder yang belum ada mengembalikan himpunan kosong, bukan melempar —
  /// perangkat yang belum pernah menyimpan gambar memang belum punya
  /// foldernya.
  ///
  /// [lebihTuaDari] menyaring berkas yang baru dibuat. Pemanggil yang hendak
  /// MEMBUANG berkas wajib memakainya: berkas yang baru lahir bisa saja masih
  /// dipegang layar yang sedang terbuka dan belum sempat dicatat ke database
  /// — lihat [SyncGambar.usiaAmanBerkasBaru].
  Future<Set<String>> daftarBerkas({
    String subfolder = folderProduk,
    Duration? lebihTuaDari,
  }) async {
    final dasar = await _folderDasar();
    final folder = Directory(p.join(dasar.path, subfolder));
    if (!folder.existsSync()) return {};
    final batas = lebihTuaDari == null
        ? null
        : DateTime.now().subtract(lebihTuaDari);
    return {
      for (final f in folder.listSync())
        if (f is File &&
            (batas == null || f.statSync().modified.isBefore(batas)))
          p.join(subfolder, p.basename(f.path)),
    };
  }

  /// Hapus file gambar. Aman dipanggil untuk path yang sudah tidak ada.
  Future<void> hapus(String relatif) async {
    final penuh = await lokasiPenuh(relatif);
    final file = File(penuh);
    if (file.existsSync()) await file.delete();
  }

  /// Apakah file gambarnya benar-benar ada di disk.
  Future<bool> ada(String? relatif) async {
    if (relatif == null || relatif.isEmpty) return false;
    return File(await lokasiPenuh(relatif)).existsSync();
  }
}
