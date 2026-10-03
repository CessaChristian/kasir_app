import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/sync/kemajuan_sync.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../data/sync/sync_service.dart';
import '../../widgets/alasan_terputus.dart';

enum KeadaanSegarkan { diam, berjalan, selesai, gagal }

/// Otak tombol refresh di header: menjalankan sinkron, mencatat keadaannya,
/// lalu menutup pita hasil sendiri setelah [lamaHasil].
///
/// Hanya refresh yang DITEKAN pengguna yang lewat sini. Sinkron otomatis di
/// latar (`SyncOtomatis`) tidak meredupkan layar — pengguna yang sedang
/// mencatat pesanan tidak boleh tiba-tiba terkunci.
class PengendaliSegarkan extends ChangeNotifier {
  final Future<HasilSync> Function() _jalankan;
  final Duration lamaHasil;

  PengendaliSegarkan({
    Future<HasilSync> Function()? jalankan,
    this.lamaHasil = const Duration(milliseconds: 1500),
  }) : _jalankan = jalankan ?? SyncService.instance.jalankan;

  KeadaanSegarkan _keadaan = KeadaanSegarkan.diam;
  HasilSync? _hasil;
  Timer? _tutup;
  bool _dibuang = false;

  KeadaanSegarkan get keadaan => _keadaan;
  HasilSync? get hasil => _hasil;
  bool get berjalan => _keadaan == KeadaanSegarkan.berjalan;

  /// Pita terlihat selama sinkron dan sesaat sesudahnya.
  bool get pitaTerlihat => _keadaan != KeadaanSegarkan.diam;

  /// Tekan dua kali saat masih berjalan tidak memulai putaran kedua.
  Future<void> segarkan() async {
    if (berjalan) return;
    _tutup?.cancel();
    _ubah(KeadaanSegarkan.berjalan);

    final hasil = await _jalankan();
    if (_dibuang) return;
    _hasil = hasil;
    _ubah(hasil.berhasil ? KeadaanSegarkan.selesai : KeadaanSegarkan.gagal);
    _tutup = Timer(lamaHasil, () => _ubah(KeadaanSegarkan.diam));
  }

  void _ubah(KeadaanSegarkan k) {
    if (_dibuang) return;
    _keadaan = k;
    notifyListeners();
  }

  @override
  void dispose() {
    _dibuang = true;
    _tutup?.cancel();
    super.dispose();
  }
}

/// Isi pita: ikon, judul, keterangan.
typedef TeksPita = ({IconData ikon, String judul, String keterangan});

/// Kalimat pita untuk tiap keadaan. Dipisah dari widget supaya bisa diuji.
TeksPita teksPita(
  KeadaanSegarkan keadaan,
  HasilSync? hasil,
  KemajuanSync? kemajuan,
) {
  switch (keadaan) {
    case KeadaanSegarkan.diam:
    case KeadaanSegarkan.berjalan:
      return (
        ikon: Icons.sync_rounded,
        judul: 'Menyinkronkan data…',
        keterangan: kemajuan == null
            ? 'Menghubungi server'
            : '${(kemajuan.rasio * 100).round()}%',
      );
    case KeadaanSegarkan.selesai:
      // `berubah`, BUKAN `diperiksa` — lihat catatan di HasilSync.
      final h = hasil!;
      return (
        ikon: Icons.check_circle_rounded,
        judul: h.berubah > 0
            ? '${h.berubah} data diperbarui'
            : h.didorong > 0
            ? '${h.didorong} data terkirim'
            : 'Data sudah terbaru',
        keterangan: 'Barusan',
      );
    case KeadaanSegarkan.gagal:
      final h = hasil!;
      if (h.sebagian) {
        return (
          ikon: Icons.cloud_sync_rounded,
          judul: 'Sebagian data belum tersinkron',
          keterangan: 'Akan dicoba lagi',
        );
      }
      return (
        ikon: Icons.cloud_off_rounded,
        judul: 'Gagal menyegarkan',
        keterangan: alasanTakPulihSendiri(h.sebabTerputus) ?? 'Periksa koneksi',
      );
  }
}
