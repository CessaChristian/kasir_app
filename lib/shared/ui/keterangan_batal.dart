import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// "Dibatalkan · nama, jam" lalu "Alasan: …" di bawah baris yang
/// dibatalkan (Riwayat, Pengeluaran, Detail Shift).
///
/// Desain menulis "Dihapus"; labelnya "Dibatalkan" karena transaksi dan
/// pengeluaran tidak pernah dihapus.
class KeteranganBatal extends StatelessWidget {
  final DateTime waktu;
  final String? nama;

  /// Null untuk yang terhapus SEBELUM fitur pembatalan ada.
  final String? alasan;

  /// Riwayat menaruhnya di bawah nominal (rata kanan).
  final bool rataKanan;
  final double ukuran;

  const KeteranganBatal({
    super.key,
    required this.waktu,
    required this.nama,
    required this.alasan,
    this.rataKanan = false,
    this.ukuran = TeksTeras.kecil,
  });

  static const _merah = Color(0xFFC0392B);

  @override
  Widget build(BuildContext context) {
    final jam = DateFormat('HH:mm').format(waktu.toLocal());
    final siapaKapan = nama == null ? jam : '$nama, $jam';
    final teksAlasan = 'Alasan: ${alasan ?? 'tidak tercatat'}';
    final rata = rataKanan ? TextAlign.right : TextAlign.left;
    final abu = TextStyle(
      fontSize: ukuran,
      height: 1.4,
      color: WarnaTeras.teksPudar,
    );
    // Satu Text.rich, bukan Row: boleh turun baris di layar sempit atau huruf
    // yang diperbesar, alih-alih tumpah ke samping.
    return Column(
      crossAxisAlignment: rataKanan
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 3),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Dibatalkan',
                style: TextStyle(fontWeight: FontWeight.w700, color: _merah),
              ),
              TextSpan(text: ' · $siapaKapan'),
            ],
          ),
          textAlign: rata,
          style: abu,
        ),
        Text(teksAlasan, textAlign: rata, style: abu),
      ],
    );
  }
}
