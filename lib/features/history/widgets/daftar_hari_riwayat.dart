import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nama_tercatat.dart';
import '../../../shared/ui/pita_hari.dart';
import '../../../utils/currency_formatter.dart';
import '../../sales/repositories/sales_repository.dart';
import '../models/kelompok_riwayat.dart';
import 'baris_transaksi.dart';
import 'batalkan_transaksi.dart';

/// Riwayat per hari (desain): pita oranye "Kamis, 1 Okt 2026 · N Transaksi
/// · total" yang bisa dilipat, berisi baris transaksi dengan tombol
/// batalkan (kalau boleh) dan detail struk. Dipakai Riwayat owner dan kasir.
class DaftarHariRiwayat extends StatelessWidget {
  final List<HariRiwayat> hari;
  final SalesRepository repo;

  /// Nama akun per id — untuk "Dibatalkan · nama, jam".
  final Map<String, String> nama;

  /// Hari yang sedang dilipat.
  final Set<DateTime> terlipat;
  final ValueChanged<DateTime> onLipat;

  const DaftarHariRiwayat({
    super.key,
    required this.hari,
    required this.repo,
    required this.nama,
    required this.terlipat,
    required this.onLipat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in hari) ...[
          PitaHari(
            judul: DateFormat('EEEE, d MMM yyyy', 'id_ID').format(h.tanggal),
            keterangan: '${h.isi.length} Transaksi',
            total: formatRp(h.total),
            terbuka: !terlipat.contains(h.tanggal),
            onTap: () => onLipat(h.tanggal),
            isi: [
              for (final t in h.isi)
                BarisTransaksi(
                  transaksi: t,
                  namaPembatal: t.namaPembatal(nama),
                  onTap: () => bukaDetailTransaksi(context, repo, t),
                  onBatalkan: repo.bolehDibatalkan(t)
                      ? () => batalkanTransaksiLewatDialog(context, repo, t)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
