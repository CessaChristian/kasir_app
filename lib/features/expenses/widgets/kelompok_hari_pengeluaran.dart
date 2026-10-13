import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nama_tercatat.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/ringkasan_pengeluaran.dart';
import '../repositories/expense_repository.dart';
import 'baris_pengeluaran.dart';
import 'batalkan_pengeluaran.dart';

/// Pengeluaran satu hari (desain "Rincian Pengeluaran"): "Kamis, 1 Okt 2026"
/// + total merah, lalu kartu berisi barisnya. Dipakai Pengeluaran owner dan
/// kasir.
class KelompokHariPengeluaran extends StatelessWidget {
  final HariPengeluaran hari;
  final ExpenseRepository repo;

  /// Nama akun per id — untuk pencatat dan pembatal.
  final Map<String, String> nama;

  /// Tampilkan nama pencatat di tiap baris (owner melihat semua kasir).
  final bool tampilkanPencatat;

  const KelompokHariPengeluaran({
    super.key,
    required this.hari,
    required this.repo,
    required this.nama,
    this.tampilkanPencatat = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMM yyyy', 'id_ID').format(hari.tanggal),
                  style: const TextStyle(
                    fontSize: TeksTeras.angka,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
              ),
              Text(
                '-${formatRp(hari.total)}',
                style: const TextStyle(
                  fontSize: TeksTeras.angka,
                  fontWeight: FontWeight.w600,
                  color: WarnaTeras.merah,
                ),
              ),
            ],
          ),
        ),
        KartuTeras(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final e in hari.isi)
                BarisPengeluaran(
                  pengeluaran: e,
                  namaPencatat: tampilkanPencatat ? e.namaPencatat(nama) : null,
                  namaPembatal: e.namaPembatal(nama),
                  onBatalkan: repo.bolehDibatalkan(e)
                      ? () => batalkanPengeluaranLewatDialog(context, repo, e)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
