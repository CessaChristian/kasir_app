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
  /// ke folder sementara khusus dulu.
  ///
  /// Dulu berkasnya tidak pernah dihapus dan menumpuk. Tidak dihapus tepat
  /// sesudah dibagikan: aplikasi tujuan (Gmail, Drive) bisa baru membacanya
  /// belakangan. Yang dibuang adalah sisa bagikan sebelumnya yang sudah
  /// lebih dari [umurSisaBagikan].
  static Future<void> bagikan({
    required String nama,
    required String mime,
    required Uint8List bita,
    String? subjek,
  }) async {
    final folder = Directory('${(await getTemporaryDirectory()).path}/laporan');
    await folder.create(recursive: true);
    await buangSisaBagikan(folder);
    final jalur = '${folder.path}/$nama';
    await File(jalur).writeAsBytes(bita);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(jalur, mimeType: mime)],
        subject: subjek,
      ),
    );
  }
}

const umurSisaBagikan = Duration(days: 1);

/// Buang berkas di [folder] yang lebih tua dari [umur]. Galat diabaikan —
/// berkas yang sedang dipakai aplikasi lain dicoba lagi lain kali.
Future<void> buangSisaBagikan(
  Directory folder, {
  Duration umur = umurSisaBagikan,
  DateTime? sekarang,
}) async {
  final batas = (sekarang ?? DateTime.now()).subtract(umur);
  if (!await folder.exists()) return;
  await for (final f in folder.list()) {
    if (f is! File) continue;
    try {
      if ((await f.lastModified()).isBefore(batas)) await f.delete();
    } catch (_) {}
  }
}

class BerkasTidakTersimpan implements Exception {
  final String pesan;
  const BerkasTidakTersimpan(this.pesan);

  @override
  String toString() => pesan;
}
