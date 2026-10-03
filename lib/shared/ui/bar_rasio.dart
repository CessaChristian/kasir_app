import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Bar dua warna yang membandingkan dua jumlah, mis. transaksi Tunai vs
/// QRIS, beserta keterangannya di bawah.
class BarRasio extends StatelessWidget {
  final int kiri;
  final int kanan;
  final String labelKiri;
  final String labelKanan;
  final Color warnaKiri;
  final Color warnaKanan;

  const BarRasio({
    super.key,
    required this.kiri,
    required this.kanan,
    required this.labelKiri,
    required this.labelKanan,
    this.warnaKiri = WarnaTeras.hijau,
    this.warnaKanan = WarnaTeras.biru,
  });

  @override
  Widget build(BuildContext context) {
    final total = kiri + kanan;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: total == 0
                ? Container(color: WarnaTeras.garis)
                : Row(
                    children: [
                      if (kiri > 0)
                        Expanded(
                          flex: kiri,
                          child: Container(color: warnaKiri),
                        ),
                      if (kanan > 0)
                        Expanded(
                          flex: kanan,
                          child: Container(color: warnaKanan),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _keterangan(warnaKiri, labelKiri),
            _keterangan(warnaKanan, labelKanan),
          ],
        ),
      ],
    );
  }

  Widget _keterangan(Color warna, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: warna,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: WarnaTeras.teks),
        ),
      ],
    );
  }
}
