import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/ui/keterangan_batal.dart';
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
                    if (batal)
                      KeteranganBatal(
                        waktu: t.deletedAt!,
                        nama: namaPembatal,
                        alasan: t.cancelReason,
                        rataKanan: true,
                      ),
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
}

/// Baris transaksi di Detail Shift (desain): ikon metode · jam · metode di
/// kiri, nominal dan panah di kanan, dalam kartu putihnya sendiri.
class BarisTransaksiShift extends StatelessWidget {
  final Transaction transaksi;
  final String? namaPembatal;
  final VoidCallback onTap;

  const BarisTransaksiShift({
    super.key,
    required this.transaksi,
    required this.onTap,
    this.namaPembatal,
  });

  @override
  Widget build(BuildContext context) {
    final t = transaksi;
    final batal = t.deletedAt != null;
    final qris = t.paymentMethod == 'qris';
    return Material(
      color: WarnaTeras.kartu,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                qris ? Icons.qr_code_2_rounded : Icons.payments_rounded,
                size: 22,
                color: batal
                    ? WarnaTeras.teksSamar
                    : qris
                    ? WarnaTeras.biru
                    : WarnaTeras.hijau,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: batal ? 0.6 : 1,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(t.createdAt.toLocal()),
                            style: const TextStyle(
                              fontSize: TeksTeras.angka,
                              fontWeight: FontWeight.w700,
                              color: WarnaTeras.teks,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              qris ? 'QRIS' : 'Cash',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: TeksTeras.kecil,
                                color: WarnaTeras.teksSamar,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (batal)
                      KeteranganBatal(
                        waktu: t.deletedAt!,
                        nama: namaPembatal,
                        alasan: t.cancelReason,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRp(t.total),
                style: TextStyle(
                  fontSize: TeksTeras.angka,
                  fontWeight: FontWeight.w700,
                  color: batal ? WarnaTeras.teksSamar : WarnaTeras.teks,
                  decoration: batal ? TextDecoration.lineThrough : null,
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
}
