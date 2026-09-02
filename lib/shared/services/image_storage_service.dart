import 'dart:io';

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
class ImageStorageService {
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

  /// Simpan gambar dari [sumber] sebagai WebP di folder permanen.
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

    final namaFile = '${newUuid()}.webp';
    final tujuan = p.join(tujuanFolder.path, namaFile);

    final hasil = await FlutterImageCompress.compressAndGetFile(
      sumber.absolute.path,
      tujuan,
      format: CompressFormat.webp,
      minWidth: _sisiMaksimal,
      minHeight: _sisiMaksimal,
      quality: _kualitas,
    );

    if (hasil == null) {
      // Encoder WebP bisa gagal pada format yang tidak didukung. Daripada
      // kehilangan gambarnya, salin apa adanya ke folder permanen — yang
      // penting file tidak tertinggal di cache.
      final cadangan = p.join(tujuanFolder.path, '${newUuid()}${p.extension(sumber.path)}');
      await sumber.copy(cadangan);
      return p.join(subfolder, p.basename(cadangan));
    }

    return p.join(subfolder, p.basename(hasil.path));
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
