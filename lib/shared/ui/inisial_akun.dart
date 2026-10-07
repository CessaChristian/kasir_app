import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Kotak oranye muda berisi huruf pertama nama akun (Riwayat Shift, Kelola
/// Kasir).
class InisialKasir extends StatelessWidget {
  final String nama;
  final double ukuran;

  const InisialKasir({super.key, required this.nama, required this.ukuran});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ukuran,
      height: ukuran,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WarnaTeras.oranyeLembut,
        borderRadius: BorderRadius.circular(ukuran * 0.28),
      ),
      child: Text(
        nama.isEmpty ? '?' : nama.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: ukuran * 0.45,
          fontWeight: FontWeight.w700,
          color: WarnaTeras.oranye,
        ),
      ),
    );
  }
}
