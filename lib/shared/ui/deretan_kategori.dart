import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Satu chip di [DeretanKategori]. [id] null = "Semua".
class ChipKategori {
  final String? id;
  final String label;
  final IconData ikon;

  const ChipKategori({
    required this.id,
    required this.label,
    required this.ikon,
  });
}

/// Deretan chip kategori yang digeser ke samping, melebar sampai tepi
/// layar. Dipakai halaman Produk; nanti juga halaman Kasir.
class DeretanKategori extends StatelessWidget {
  final List<ChipKategori> isi;
  final String? terpilih;
  final ValueChanged<String?> onPilih;

  /// Jarak tepi halaman — chip pertama sejajar isi halaman, tapi deretannya
  /// tetap bisa digeser sampai tepi layar.
  final double tepi;

  const DeretanKategori({
    super.key,
    required this.isi,
    required this.terpilih,
    required this.onPilih,
    this.tepi = 16,
  });

  /// Oranye chip terpilih di desain (#FF911D), sedikit beda dari oranye merek.
  static const _oranyeTerpilih = Color(0xFFFF911D);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OverflowBox(
        maxWidth: MediaQuery.sizeOf(context).width,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(tepi, 0, tepi, 6),
          children: [
            for (final c in isi)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chip(c, c.id == terpilih),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ChipKategori c, bool aktif) {
    return Container(
      decoration: BoxDecoration(
        color: aktif ? _oranyeTerpilih : WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C230A).withValues(alpha: 0.10),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onPilih(c.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  c.ikon,
                  size: 18,
                  color: aktif ? Colors.white : WarnaTeras.oranye,
                ),
                const SizedBox(width: 6),
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: aktif ? Colors.white : WarnaTeras.teks,
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
