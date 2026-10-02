import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../features/sales/models/pilihan_produk.dart';

/// Ikon kecil penanda kelompok pilihan yang dinyalakan di sebuah produk.
class IkonPilihanProduk extends StatelessWidget {
  final Product produk;
  final double ukuran;

  const IkonPilihanProduk({super.key, required this.produk, this.ukuran = 13});

  static const _ikon = {
    KelompokPilihan.pedas: (Icons.local_fire_department_rounded, Colors.deepOrange),
    KelompokPilihan.manis: (Icons.cookie_rounded, Colors.brown),
    KelompokPilihan.es: (Icons.ac_unit_rounded, Colors.lightBlue),
  };

  @override
  Widget build(BuildContext context) {
    final kelompok = kelompokUntuk(produk);
    if (kelompok.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in kelompok)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Icon(_ikon[k]!.$1, size: ukuran, color: _ikon[k]!.$2),
          ),
      ],
    );
  }
}
