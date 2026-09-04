import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mengunci izin INTERNET di manifest Android yang dipakai build RELEASE.
///
/// Latar belakang — Flutter otomatis menambahkan izin ini di manifest `debug`
/// dan `profile` supaya hot reload bisa jalan, TAPI TIDAK di manifest `main`
/// yang dipakai build release. Template bawaan memang begitu.
///
/// Akibatnya APK release sama sekali tidak bisa mengakses jaringan: setiap
/// panggilan ke Supabase gagal, dan aplikasi terus menampilkan layar
/// "Perlu Internet" meski WiFi menyala dan server bisa di-ping dari HP yang
/// sama.
///
/// Yang membuatnya sulit ditemukan: build debug di emulator berjalan mulus
/// karena manifest debug punya izinnya. Masalahnya baru muncul setelah APK
/// release dipasang di perangkat sungguhan — dan tidak ada pesan error yang
/// menyebut soal izin.
void main() {
  test('manifest utama memuat izin INTERNET', () {
    final f = File('android/app/src/main/AndroidManifest.xml');
    expect(f.existsSync(), isTrue, reason: 'manifest utama harus ada');

    expect(
      f.readAsStringSync().contains('android.permission.INTERNET'),
      isTrue,
      reason: 'Tanpa izin ini, build RELEASE tidak bisa menghubungi server '
          'sama sekali. Build debug tetap jalan karena manifest debug punya '
          'izinnya sendiri — jadi kelalaian ini TIDAK akan terlihat sampai '
          'APK release dipasang di HP sungguhan.',
    );
  });
}
