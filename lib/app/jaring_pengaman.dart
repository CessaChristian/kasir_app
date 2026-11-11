import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/pemulihan/pemulihan_data.dart';
import '../data/pemulihan/penjaga_database.dart';
import '../features/pemulihan/layar_data_rusak.dart';
import '../shared/services/catatan_error.dart';

/// Pasang penangkap error tak terduga untuk seluruh aplikasi (audit 6 Nov
/// nomor 62). Semuanya masuk [CatatanError] dan dikirim ke server.
///
/// Tanpa ini, di APK rilis layar yang gagal digambar jadi kotak abu-abu dan
/// tombol yang gagal diam saja — tanpa pesan, tanpa jejak.
void pasangJaringPengaman() {
  // Gagal menggambar layar, galat di gestur dan animasi.
  final bawaan = FlutterError.onError;
  FlutterError.onError = (rincian) {
    bawaan?.call(rincian);
    CatatanError.instance.catat(
      rincian.exception,
      rincian.stack,
      sumber: 'tampilan',
    );
  };
  // Galat di pekerjaan latar yang tidak ditangkap siapa pun.
  PlatformDispatcher.instance.onError = (galat, jejak) {
    debugPrint('[galat latar] $galat\n$jejak');
    CatatanError.instance.catat(galat, jejak, sumber: 'latar');
    return true;
  };
  // Di rilis saja: saat mengembangkan, layar merah berisi rinciannya lebih
  // berguna.
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const BagianGagalTampil();
  }
}

/// Pengganti bagian layar yang gagal digambar. Tidak bergantung pada tema
/// atau widget di atasnya — bisa muncul di mana saja.
class BagianGagalTampil extends StatelessWidget {
  const BagianGagalTampil({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFFFF1E2),
      alignment: Alignment.center,
      child: const Text(
        'Bagian ini gagal ditampilkan. Coba buka ulang halamannya.',
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF5C534C),
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Menggantikan seluruh aplikasi dengan layar Data Rusak begitu
/// [PenjagaDatabase] membuktikan berkas database rusak — dari halaman mana
/// pun. Dipasang di `MaterialApp.builder`, di atas Navigator.
class PenutupDataRusak extends StatelessWidget {
  final Widget child;
  final PenjagaDatabase? penjaga;

  /// Pengganti menutup aplikasi, untuk test.
  final Future<void> Function()? onTutup;

  const PenutupDataRusak({
    super.key,
    required this.child,
    this.penjaga,
    this.onTutup,
  });

  static Future<void> _tutupAplikasi() async {
    await SystemNavigator.pop();
    // Prosesnya benar-benar diakhiri: saat dibuka lagi, pemeriksaan awal
    // jalan dari nol dan menampilkan Perbaiki data.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = penjaga ?? PenjagaDatabase.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: p.rusak,
      child: child,
      builder: (context, rusak, anak) {
        if (!rusak) return anak!;
        return FutureBuilder<RingkasanCadangan?>(
          future: p.ringkasan(),
          builder: (context, snap) => LayarDataRusak(
            ringkasan: snap.data,
            perluTutup: true,
            onPerbaiki: onTutup ?? _tutupAplikasi,
          ),
        );
      },
    );
  }
}
