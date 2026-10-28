import 'dart:async';

import 'package:flutter/widgets.dart';

/// Memberi tahu saat tanggal berganti selagi halaman terbuka.
///
/// Halaman Laporan, Riwayat, Pengeluaran, dan Riwayat Shift menyimpan
/// "hari ini" saat dibuka. Dibiarkan terbuka lewat tengah malam, isinya tetap
/// hari kemarin. Pengawas ini bangun tepat sesudah tengah malam, dan
/// memeriksa lagi setiap aplikasi kembali ke depan (timer bisa tertunda
/// selama aplikasi di latar belakang).
class PengawasHari {
  PengawasHari({required this.onGanti, DateTime Function()? jam})
    : _jam = jam ?? DateTime.now {
    _hari = _tanggal(_jam());
    _jadwalkan();
    _siklus = AppLifecycleListener(onResume: periksa);
  }

  /// Dipanggil dengan tanggal lama dan tanggal baru.
  final void Function(DateTime lama, DateTime baru) onGanti;
  final DateTime Function() _jam;

  late DateTime _hari;
  Timer? _timer;
  late final AppLifecycleListener _siklus;

  static DateTime _tanggal(DateTime d) => DateTime(d.year, d.month, d.day);

  void _jadwalkan() {
    _timer?.cancel();
    final sekarang = _jam();
    final besok = DateTime(sekarang.year, sekarang.month, sekarang.day + 1);
    _timer = Timer(
      besok.difference(sekarang) + const Duration(seconds: 1),
      periksa,
    );
  }

  /// Bandingkan tanggal sekarang dengan yang terakhir diketahui.
  void periksa() {
    final hari = _tanggal(_jam());
    if (hari != _hari) {
      final lama = _hari;
      _hari = hari;
      onGanti(lama, hari);
    }
    _jadwalkan();
  }

  void dispose() {
    _timer?.cancel();
    _siklus.dispose();
  }
}
