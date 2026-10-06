import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Simpan atau bagikan berkas buatan aplikasi (mis. Laporan PDF/Excel).
abstract final class SimpanBerkas {
  static const _kanal = MethodChannel('kasir_app/unduhan');

  /// Simpan ke folder Download HP (MediaStore, Android 10 ke atas, tanpa
  /// izin). Nama yang sudah ada diberi akhiran "(1)" oleh Android sendiri.
  ///
  /// Melempar [BerkasTidakTersimpan] berisi pesan yang siap ditampilkan.
  static Future<void> keDownload({
    required String nama,
    required String mime,
    required Uint8List bita,
  }) async {
    try {
      await _kanal.invokeMethod<String>('simpanKeDownload', {
        'nama': nama,
        'mime': mime,
        'bita': bita,
      });
    } on PlatformException catch (e) {
      throw BerkasTidakTersimpan(
        e.code == 'TIDAK_DIDUKUNG'
            ? 'Simpan ke HP butuh Android 10 ke atas. Pakai Bagikan.'
            : 'Gagal menyimpan laporan: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      // Kode Android-nya tidak ada di aplikasi yang terpasang (versi lama,
      // atau di pengembangan: belum dipasang ulang setelah kodenya berubah).
      throw const BerkasTidakTersimpan(
        'Simpan ke HP belum tersedia di versi aplikasi ini. Pakai Bagikan.',
      );
    }
  }

  /// Buka menu bagikan bawaan (WhatsApp, email, Drive, …). Berkasnya ditulis
  /// ke folder sementara dulu.
  static Future<void> bagikan({
    required String nama,
    required String mime,
    required Uint8List bita,
    String? subjek,
  }) async {
    final jalur = '${(await getTemporaryDirectory()).path}/$nama';
    await File(jalur).writeAsBytes(bita);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(jalur, mimeType: mime)],
        subject: subjek,
      ),
    );
  }
}

class BerkasTidakTersimpan implements Exception {
  final String pesan;
  const BerkasTidakTersimpan(this.pesan);

  @override
  String toString() => pesan;
}
