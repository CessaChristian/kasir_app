import 'package:flutter/material.dart';

import '../../features/sales/models/pilihan_produk.dart';
import 'warna_teras.dart';

/// Gaya tiap kelompok pilihan di desain: (ikon, warna, latar lembut, latar
/// sakelar menyala).
({IconData ikon, Color warna, Color lembut, Color jalur}) gayaPilihan(
  KelompokPilihan k,
) => switch (k) {
  KelompokPilihan.pedas => (
    ikon: Icons.local_fire_department_rounded,
    warna: WarnaTeras.merah,
    lembut: const Color(0xFFFFE9E7),
    jalur: WarnaTeras.merahIkon,
  ),
  KelompokPilihan.manis => (
    ikon: Icons.cookie_rounded,
    warna: WarnaTeras.oranye,
    lembut: WarnaTeras.oranyeMuda,
    jalur: const Color(0xFFFDE3C8),
  ),
  KelompokPilihan.es => (
    ikon: Icons.ac_unit_rounded,
    warna: WarnaTeras.biru,
    lembut: const Color(0xFFE8F0FB),
    jalur: const Color(0xFFD6E4F8),
  ),
};

/// Bulatan ikon kecil per kelompok pilihan (🔥 / 🍪 / ❄).
class BulatanPilihan extends StatelessWidget {
  final KelompokPilihan kelompok;

  const BulatanPilihan(this.kelompok, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = gayaPilihan(kelompok);
    return Tooltip(
      message: kelompok.label,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: g.lembut, shape: BoxShape.circle),
        child: Icon(g.ikon, size: 14, color: g.warna),
      ),
    );
  }
}
