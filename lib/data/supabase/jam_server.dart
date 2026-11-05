import 'dart:io' show HttpDate, HttpException;

import 'package:flutter/foundation.dart';

/// Selisih jam HP ini dengan jam server, dibaca dari header `Date` di setiap
/// jawaban server. Tidak menambah permintaan apa pun.
///
/// Dipakai untuk dua hal: menilai tiket login tanpa tertipu jam HP, dan
/// memperingatkan kasir. Jam yang salah membuat jualan masuk ke tanggal yang
/// salah, dan selagi offline jam HP memang tidak bisa diperiksa.
class JamServer {
  JamServer._();
  static final JamServer instance = JamServer._();

  /// Selisih mulai dari sini dianggap jam HP salah. Sama dengan batas server
  /// di `supabase/tolak_versi_lama.sql`.
  static const batasSalah = Duration(minutes: 5);

  /// Jam `Date` hanya sampai detik dan jawabannya butuh waktu sampai ke HP,
  /// jadi selisih kecil tidak perlu dicatat ulang dan membangun ulang layar.
  static const _abaikan = Duration(seconds: 30);

  /// Jam HP dikurangi jam server: positif berarti jam HP lebih cepat. Null
  /// kalau belum pernah mendapat jawaban server sejak aplikasi dibuka.
  final ValueNotifier<Duration?> selisih = ValueNotifier(null);

  bool get jamSalah {
    final s = selisih.value;
    return s != null && s.abs() >= batasSalah;
  }

  /// Jam sekarang menurut server, atau jam HP kalau belum diketahui.
  DateTime sekarang() {
    final s = selisih.value;
    final hp = DateTime.now();
    return s == null ? hp : hp.subtract(s);
  }

  /// Header yang tidak ada atau tidak terbaca diabaikan.
  void catat(String? headerDate, {DateTime? jamHp}) {
    if (headerDate == null) return;
    final DateTime server;
    try {
      server = HttpDate.parse(headerDate);
    } on HttpException {
      return;
    }
    final baru = (jamHp ?? DateTime.now()).difference(server);
    final lama = selisih.value;
    if (lama != null && (baru - lama).abs() < _abaikan) return;
    selisih.value = baru;
  }

  /// "lebih cepat 1 hari", "lebih lambat 3 jam".
  static String keterangan(Duration selisih) {
    final arah = selisih.isNegative ? 'lebih lambat' : 'lebih cepat';
    final d = selisih.abs();
    final lama = d.inDays >= 1
        ? '${d.inDays} hari'
        : d.inHours >= 1
            ? '${d.inHours} jam'
            : '${d.inMinutes} menit';
    return '$arah $lama';
  }

  @visibleForTesting
  void aturUlang() => selisih.value = null;
}
