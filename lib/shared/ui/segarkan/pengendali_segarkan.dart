import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/sync/kemajuan_sync.dart';
import '../../../data/sync/sinkron_berbatas.dart';
import '../../../data/sync/sync_engine.dart';
import '../../widgets/alasan_terputus.dart';

enum KeadaanSegarkan { diam, berjalan, selesai }

/// Otak tombol refresh di header: menjalankan sinkron, mencatat keadaannya,
/// lalu menutup pita hasil sendiri setelah [lamaHasil].
///
/// Hanya refresh yang DITEKAN pengguna yang lewat sini. Sinkron otomatis di
/// latar (`SyncOtomatis`) tidak meredupkan layar — pengguna yang sedang
/// mencatat pesanan tidak boleh tiba-tiba terkunci.
///
/// Gagal (termasuk belum tersambung dalam 5 detik, lihat [sinkronBerbatas])
/// TIDAK ditulis di pita: pita langsung menutup, layar dilepas, dan
/// [onGagal] dipanggil supaya halaman menampilkan AppToast.
class PengendaliSegarkan extends ChangeNotifier {
  final Future<HasilSync> Function()? _jalankan;
  final ValueNotifier<KemajuanSync?>? _kemajuan;
  final Duration batasTersambungUji;
  final Duration lamaHasil;

  /// Dipasang halaman (yang punya `context`) untuk menampilkan AppToast.
  void Function(String pesan, {required bool sebagian})? onGagal;

  PengendaliSegarkan({
    Future<HasilSync> Function()? jalankan,
    ValueNotifier<KemajuanSync?>? kemajuan,
    this.batasTersambungUji = batasTersambung,
    this.lamaHasil = const Duration(milliseconds: 1500),
  }) : _jalankan = jalankan,
       _kemajuan = kemajuan;

  KeadaanSegarkan _keadaan = KeadaanSegarkan.diam;
  HasilSync? _hasil;
  Timer? _tutup;
  bool _dibuang = false;

  KeadaanSegarkan get keadaan => _keadaan;
  HasilSync? get hasil => _hasil;
  bool get berjalan => _keadaan == KeadaanSegarkan.berjalan;

  /// Pita terlihat selama sinkron dan sesaat setelah berhasil.
  bool get pitaTerlihat => _keadaan != KeadaanSegarkan.diam;

  /// Tekan dua kali saat masih berjalan tidak memulai putaran kedua.
  Future<void> segarkan() async {
    if (berjalan) return;
    _tutup?.cancel();
    _ubah(KeadaanSegarkan.berjalan);

    final hasil = await sinkronBerbatas(
      jalankan: _jalankan,
      kemajuan: _kemajuan,
      batas: batasTersambungUji,
    );
    if (_dibuang) return;
    _hasil = hasil;
    if (hasil.berhasil) {
      _ubah(KeadaanSegarkan.selesai);
      _tutup = Timer(lamaHasil, () => _ubah(KeadaanSegarkan.diam));
    } else {
      _ubah(KeadaanSegarkan.diam);
      final p = pesanGagalSinkron(hasil);
      onGagal?.call(p.pesan, sebagian: p.sebagian);
    }
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
  if (keadaan == KeadaanSegarkan.selesai) {
    // `berubah`, BUKAN `diperiksa` — lihat catatan di HasilSync.
    final h = hasil!;
    return (
      ikon: Icons.check_circle_rounded,
      judul: h.berubah > 0
          ? '${h.berubah} data diperbarui'
          : h.didorong > 0
          ? '${h.didorong} data terkirim'
          : 'Data sudah terbaru',
      keterangan: 'Selesai',
    );
  }
  return (
    ikon: Icons.sync_rounded,
    judul: 'Menyinkronkan data…',
    keterangan: kemajuan == null
        ? 'Menghubungi server'
        : '${(kemajuan.rasio * 100).round()}%',
  );
}
