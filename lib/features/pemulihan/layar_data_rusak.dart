import 'package:flutter/material.dart';

import '../../data/pemulihan/pemulihan_data.dart';
import '../../shared/ui/teks_teras.dart';
import '../../shared/ui/warna_teras.dart';
import '../../shared/widgets/app_toast.dart';
import '../../utils/pesan_galat.dart';

/// Kabar sesudah Perbaiki data selesai. Sebagian gagal tidak boleh lewat
/// sebagai toast yang hilang sendiri: kasir harus mencocokkan dengan nota.
void beritahuHasilPemulihan(BuildContext context, HasilPemulihan hasil) {
  if (hasil.gagal == 0) {
    AppToast.success(context, 'Perbaikan data berhasil');
    return;
  }
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sebagian data tidak kembali'),
      content: Text(
        '${hasil.gagal} data belum terkirim tidak bisa dipulihkan. '
        'Cocokkan dengan nota dan hubungi owner.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Mengerti'),
        ),
      ],
    ),
  );
}

/// Layar pertama kalau berkas database di HP ini terbukti rusak.
class LayarDataRusak extends StatefulWidget {
  /// Null kalau salinan data yang belum terkirim tidak bisa dibaca.
  final RingkasanCadangan? ringkasan;
  final Future<void> Function() onPerbaiki;

  /// True = kerusakannya ketahuan DI TENGAH pemakaian (PenjagaDatabase).
  /// Database sedang terbuka dan tidak bisa diganti, jadi tombolnya menutup
  /// aplikasi; Perbaiki data muncul saat dibuka lagi. [onPerbaiki] lalu
  /// berarti "tutup aplikasi".
  final bool perluTutup;

  // true = transaksi yang baru saja dibayar tidak tersimpan dan kasir harus mengulang sesudah data diperbaiki
  final bool transaksiTidakTersimpan;

  const LayarDataRusak({
    super.key,
    required this.ringkasan,
    required this.onPerbaiki,
    this.perluTutup = false,
    this.transaksiTidakTersimpan = false,
  });

  /// Kalimat tentang data yang belum terkirim.
  static String kalimatCadangan(RingkasanCadangan? r) {
    if (r == null) {
      return 'Data yang belum terkirim tidak bisa diselamatkan. '
          'Sesudah diperbaiki, cocokkan lagi dengan nota. '
          'Yang sudah terkirim tetap aman di server.';
    }
    if (r.transaksi > 0) {
      return '${r.transaksi} transaksi yang belum terkirim masih aman.';
    }
    if (r.semua > 0) return '${r.semua} data yang belum terkirim masih aman.';
    return 'Semua data sudah terkirim ke server.';
  }

  @override
  State<LayarDataRusak> createState() => _LayarDataRusakState();
}

class _LayarDataRusakState extends State<LayarDataRusak> {
  bool _memperbaiki = false;
  String? _galat;

  Future<void> _perbaiki() async {
    setState(() {
      _memperbaiki = true;
      _galat = null;
    });
    try {
      await widget.onPerbaiki();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memperbaiki = false;
        _galat = pesanGalat(e, awalan: 'Gagal memperbaiki data');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarnaTeras.latar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.build_circle_outlined,
                  size: 64,
                  color: WarnaTeras.oranye,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Data di HP ini rusak',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TeksTeras.judul,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
                if (widget.transaksiTidakTersimpan) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: WarnaTeras.merahMuda,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Transaksi barusan TIDAK tersimpan. Ulangi transaksinya '
                      'sesudah data diperbaiki.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w600,
                        color: WarnaTeras.merah,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  LayarDataRusak.kalimatCadangan(widget.ringkasan),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.perluTutup
                      ? 'Tidak perlu install ulang. Tutup aplikasi ini, lalu '
                            'buka lagi dan ketuk Perbaiki data.'
                      : 'Tidak perlu install ulang. Ketuk Perbaiki data, lalu HP ini '
                            'mengambil lagi datanya dari server. Pastikan ada internet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
                if (_galat != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _galat!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TeksTeras.biasa,
                      color: Colors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _memperbaiki ? null : _perbaiki,
                    style: FilledButton.styleFrom(
                      backgroundColor: WarnaTeras.oranye,
                    ),
                    child: Text(
                      widget.perluTutup
                          ? 'Tutup aplikasi'
                          : _memperbaiki
                          ? 'Memperbaiki…'
                          : 'Perbaiki data',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
