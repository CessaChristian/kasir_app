import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mengunci aturan: pada pemasangan pertama, aplikasi WAJIB bertanya ke server
/// sebelum menyimpulkan bahwa bisnis ini belum punya akun.
///
/// Latar belakang — `main()` menjalankan sinkron di latar belakang TANPA
/// ditunggu, lalu langsung `runApp()`. Akibatnya `AuthFlowHandler` memeriksa
/// `hasAnyUser()` saat database masih kosong, menyimpulkan "belum ada akun",
/// dan menampilkan layar **Setup Akun Owner** — padahal 4 akun sedang dalam
/// perjalanan dari server. Layarnya tidak pernah diperiksa ulang setelah data
/// masuk.
///
/// Bahayanya nyata dan permanen: pemilik memasang aplikasi di HP barunya,
/// melihat "Setup Akun Owner", lalu membuat akun owner KEDUA — yang ikut
/// tersinkron ke server dan tidak bisa dibereskan dari dalam aplikasi.
///
/// Ditemukan saat menguji dua perangkat; tidak akan pernah terlihat pada satu
/// perangkat saja.
void main() {
  final main_ = File('lib/main.dart').readAsStringSync();

  /// Isi fungsi `_checkAuthState`, tanpa komentar.
  String badanPemeriksaan() {
    final i = main_.indexOf('Future<AuthState> _checkAuthState()');
    expect(i, isNot(-1), reason: '_checkAuthState harus ada di main.dart');
    final sisa = main_.substring(i);
    final akhir = sisa.indexOf('\n  }\n');
    return sisa
        .substring(0, akhir)
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
  }

  test('pemeriksaan awal menyinkronkan dulu sebelum menyimpulkan', () {
    final badan = badanPemeriksaan();

    expect(
      badan.contains('SyncService.instance.jalankan()'),
      isTrue,
      reason: 'Saat database lokal kosong, aplikasi HARUS menyapa server dulu. '
          'Tanpa itu, HP baru akan menawarkan pembuatan akun owner padahal '
          'akunnya sudah ada di server.',
    );

    // Sinkron harus terjadi SEBELUM keputusan "tidak ada user" diambil.
    final posSync = badan.indexOf('SyncService.instance.jalankan()');
    final posPutusan = badan.indexOf('hasUser: false');
    expect(
      posSync < posPutusan,
      isTrue,
      reason: 'Sinkron harus dijalankan SEBELUM mengembalikan hasUser: false. '
          'Kalau sesudah, keputusannya sudah telanjur diambil.',
    );

    expect(
      badan.contains('await onboardingRepo.hasAnyUser()'),
      isTrue,
      reason: 'Setelah sinkron, keberadaan user harus diperiksa ULANG — '
          'server mungkin baru saja mengirimkan akunnya.',
    );
  });

  test('gagal menghubungi server TIDAK disamakan dengan "belum ada akun"', () {
    expect(
      main_.contains('perluInternet'),
      isTrue,
      reason: 'Harus ada keadaan tersendiri untuk "server tak terjangkau". '
          'Menyamakannya dengan "belum ada akun" adalah akar bug ini.',
    );

    final badan = badanPemeriksaan();
    expect(
      badan.contains('perluInternet: true'),
      isTrue,
      reason: 'Sinkron yang gagal pada pemasangan pertama harus menghasilkan '
          'keadaan perluInternet, bukan hasUser: false.',
    );
  });

  test('layar perlu-internet tidak menawarkan jalan pintas', () {
    final i = main_.indexOf('class _LayarPerluInternet');
    expect(i, isNot(-1), reason: 'layar khusus harus ada');
    final layar = main_.substring(i);

    for (final terlarang in ['OnboardingPage', 'OwnerSetupPage']) {
      expect(
        layar.contains(terlarang),
        isFalse,
        reason: 'Layar ini TIDAK boleh menawarkan pembuatan akun. Itu persis '
            'jalan yang melahirkan akun owner ganda.',
      );
    }
  });

  test('pemakaian sehari-hari tidak diblokir saat offline', () {
    final badan = badanPemeriksaan();
    // Blok sinkron wajib dijaga `!hasUser` — kalau tidak, aplikasi akan
    // menunggu jaringan setiap kali dibuka, dan kasir gagal berjualan.
    expect(
      RegExp(r'if\s*\(\s*!hasUser\s*&&').hasMatch(badan),
      isTrue,
      reason: 'Sinkron hanya ditunggu saat database lokal KOSONG. Kalau sudah '
          'ada user, aplikasi harus jalan penuh tanpa internet.',
    );
  });
}
