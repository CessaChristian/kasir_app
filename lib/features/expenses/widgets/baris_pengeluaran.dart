import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/kategori_biaya.dart';

/// Satu baris pengeluaran: ikon · nama (+jumlah) · kategori & pencatat ·
/// nominal · tombol batalkan.
///
/// Yang dibatalkan tampil pudar, nominalnya dicoret, dengan chip
/// "Dibatalkan · jam · oleh siapa" dan alasannya.
class BarisPengeluaran extends StatelessWidget {
  final Expense pengeluaran;
  final String? namaPencatat;
  final String? namaPembatal;

  /// Null = tombol batalkan tidak tampil (tidak berhak, atau sudah batal).
  final VoidCallback? onBatalkan;

  const BarisPengeluaran({
    super.key,
    required this.pengeluaran,
    this.namaPencatat,
    this.namaPembatal,
    this.onBatalkan,
  });

  @override
  Widget build(BuildContext context) {
    final e = pengeluaran;
    final batal = e.deletedAt != null;
    final nama = e.qty > 1 ? '${e.description} (${e.qty}x)' : e.description;
    final meta = [
      KategoriBiaya.labelDari(e.category),
      ?namaPencatat,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: batal ? const Color(0xFFF1ECE7) : WarnaTeras.merahIkon,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.trending_down_rounded,
              size: 18,
              color: batal ? const Color(0xFFB8AEA5) : WarnaTeras.merah,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: batal ? WarnaTeras.teksSamar : WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
                if (batal) ..._keteranganBatal(e),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 8),
            child: Text(
              '-${formatRp(e.amount)}',
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w600,
                color: batal ? const Color(0xFFB8AEA5) : WarnaTeras.merah,
                decoration: batal ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: onBatalkan == null
                ? null
                : IconButton(
                    onPressed: onBatalkan,
                    tooltip: 'Batalkan',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 21,
                      color: WarnaTeras.merah,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Desain: "Dihapus · Owner, 01:23" lalu "Alasan: …" — tanpa chip.
  /// Labelnya "Dibatalkan" sesuai keputusan (tidak pernah dihapus).
  List<Widget> _keteranganBatal(Expense e) {
    final jam = DateFormat('HH:mm').format(e.deletedAt!.toLocal());
    final siapaKapan = namaPembatal == null ? jam : '$namaPembatal, $jam';
    // Yang terhapus SEBELUM fitur pembatalan tidak punya alasan.
    final alasan = e.cancelReason ?? 'tidak tercatat';
    const abu = TextStyle(
      fontSize: TeksTeras.kecil,
      color: WarnaTeras.teksPudar,
    );
    return [
      const SizedBox(height: 3),
      Row(
        children: [
          const Text(
            'Dibatalkan',
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC0392B),
            ),
          ),
          const Text('  ·  ', style: abu),
          Flexible(
            child: Text(
              siapaKapan,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: abu,
            ),
          ),
        ],
      ),
      const SizedBox(height: 1),
      Text('Alasan: $alasan', style: abu),
    ];
  }
}
