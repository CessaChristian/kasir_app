import 'package:flutter/material.dart';

import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';

/// Satu baris di [KartuDibatalkan].
class BarisDibatalkan {
  final String judul;
  final String keterangan;

  /// Null untuk yang dibatalkan sebelum fitur pembatalan ada.
  final String? alasan;
  final String nilai;

  const BarisDibatalkan({
    required this.judul,
    required this.keterangan,
    required this.alasan,
    required this.nilai,
  });
}

/// Kartu "Transaksi/Pengeluaran Dibatalkan" di Laporan (desain): jumlah dan
/// nilainya, lalu daftar dengan alasan. Desain menulis "Dihapus"; labelnya
/// "Dibatalkan" karena keduanya tidak pernah dihapus.
class KartuDibatalkan extends StatelessWidget {
  final IconData ikon;
  final String jumlah;
  final String nilai;
  final List<BarisDibatalkan> isi;
  final String kosong;
  final String catatan;

  const KartuDibatalkan({
    super.key,
    required this.ikon,
    required this.jumlah,
    required this.nilai,
    required this.isi,
    required this.kosong,
    required this.catatan,
  });

  static const _garisBaris = Color(0xFFF4EEE8);

  @override
  Widget build(BuildContext context) {
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: WarnaTeras.merahMuda,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(ikon, size: 20, color: WarnaTeras.merah),
              ),
              const SizedBox(width: 12),
              Expanded(child: _angka('Jumlah dibatalkan', jumlah, null)),
              _angka('Nilai', nilai, WarnaTeras.merah, kanan: true),
            ],
          ),
          if (isi.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(kosong, style: _abu),
            )
          else ...[
            const SizedBox(height: 12),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: WarnaTeras.garis)),
              ),
              child: Column(children: [for (final b in isi) _baris(b)]),
            ),
            const SizedBox(height: 10),
            Text(catatan, style: _abu),
          ],
        ],
      ),
    );
  }

  static const _abu = TextStyle(
    fontSize: TeksTeras.kecil,
    color: WarnaTeras.teksSamar,
  );

  Widget _angka(
    String label,
    String nilai,
    Color? warna, {
    bool kanan = false,
  }) {
    return Column(
      crossAxisAlignment: kanan
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: TeksTeras.keterangan,
            color: WarnaTeras.teksPudar,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          nilai,
          style: TextStyle(
            fontSize: TeksTeras.angka,
            fontWeight: FontWeight.w700,
            color: warna ?? WarnaTeras.teks,
          ),
        ),
      ],
    );
  }

  Widget _baris(BarisDibatalkan b) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _garisBaris)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.judul,
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.keterangan,
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alasan: ${b.alasan ?? 'tidak tercatat'}',
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: Color(0xFF5A5048),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            b.nilai,
            style: const TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teksSamar,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }
}
