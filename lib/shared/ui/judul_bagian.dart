import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Judul bagian bergaris oranye di kiri, mis. "Rincian Pengeluaran".
class JudulBagian extends StatelessWidget {
  final String teks;
  final double ukuran;

  const JudulBagian(
    this.teks, {
    super.key,
    this.ukuran = TeksTeras.judulBagian,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: WarnaTeras.oranye, width: 2)),
      ),
      child: Text(
        teks,
        style: TextStyle(
          fontSize: ukuran,
          color: WarnaTeras.teks,
        ),
      ),
    );
  }
}
