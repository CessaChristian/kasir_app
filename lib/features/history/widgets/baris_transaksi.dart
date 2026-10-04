import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';

/// Satu baris di Riwayat (desain): tanggal · nomor nota · toko · metode di
/// kiri, nominal di kanan, tombol batalkan dan panah.
///
/// Yang dibatalkan: latar sedikit krem, teks pudar, nominal dicoret, lalu
/// "Dibatalkan · nama, jam" dan "Alasan: …" di bawah nominal.
class BarisTransaksi extends StatelessWidget {
  final Transaction transaksi;
  final String? namaPembatal;
  final VoidCallback onTap;

  /// Null = tombol batalkan tidak tampil.
  final VoidCallback? onBatalkan;

  const BarisTransaksi({
    super.key,
    required this.transaksi,
    required this.onTap,
    this.namaPembatal,
    this.onBatalkan,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaksi;
    final batal = t.deletedAt != null;
    final warnaTeks = batal ? WarnaTeras.teksSamar : WarnaTeras.teks;
    final gayaKiri = TextStyle(
      fontSize: TeksTeras.kecil,
      height: 1.45,
      color: warnaTeks,
    );
    return Material(
      color: batal ? const Color(0xFFFCFAF8) : WarnaTeras.kartu,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: WarnaTeras.garis)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('dd/MM/yyyy').format(t.createdAt.toLocal()),
                      style: gayaKiri.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(t.invoiceNo, style: gayaKiri),
                    Text(AppConstants.storeName, style: gayaKiri),
                    Text(
                      t.paymentMethod == 'qris'
                          ? 'Transaksi QRIS'
                          : 'Transaksi Tunai',
                      style: gayaKiri,
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRpRiwayat(t.total),
                      style: TextStyle(
                        fontSize: TeksTeras.kecil,
                        fontWeight: FontWeight.w700,
                        color: batal
                            ? const Color(0xFFB8AEA5)
                            : WarnaTeras.oranye,
                        decoration: batal ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (batal) ..._keteranganBatal(t),
                  ],
                ),
              ),
              if (onBatalkan != null)
                IconButton(
                  onPressed: onBatalkan,
                  tooltip: 'Batalkan',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: WarnaTeras.merah,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: WarnaTeras.titikPasif,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _keteranganBatal(Transaction t) {
    final jam = DateFormat('HH:mm').format(t.deletedAt!.toLocal());
    final siapaKapan = namaPembatal == null ? jam : '$namaPembatal, $jam';
    const abu = TextStyle(
      fontSize: TeksTeras.kecil,
      height: 1.4,
      color: WarnaTeras.teksPudar,
    );
    return [
      const SizedBox(height: 3),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Dibatalkan',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFC0392B),
              ),
            ),
            TextSpan(text: ' · $siapaKapan'),
          ],
        ),
        textAlign: TextAlign.right,
        style: abu,
      ),
      Text(
        // Yang terhapus SEBELUM fitur pembatalan tidak punya alasan.
        'Alasan: ${t.cancelReason ?? 'tidak tercatat'}',
        textAlign: TextAlign.right,
        style: abu,
      ),
    ];
  }
}
