import 'package:flutter/material.dart';

import '../../../shared/constants/category_icons.dart';
import '../../../shared/ui/warna_teras.dart';

/// Kisi pilihan ikon kategori ([kIkonPilihanKategori]): yang terpilih
/// oranye, lainnya abu. Dipakai kartu Tambah Kategori (kecil) dan lembar
/// Edit Kategori (besar).
class PilihanIkonKategori extends StatelessWidget {
  final IconData terpilih;
  final ValueChanged<IconData> onPilih;
  final double ukuran;
  final double ukuranIkon;
  final double jarak;
  final double sudut;

  const PilihanIkonKategori({
    super.key,
    required this.terpilih,
    required this.onPilih,
    this.ukuran = 30,
    this.ukuranIkon = 19,
    this.jarak = 8,
    this.sudut = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: jarak,
      runSpacing: jarak,
      children: [
        for (final ikon in kIkonPilihanKategori)
          Material(
            color: ikon == terpilih ? WarnaTeras.oranye : WarnaTeras.latarAbu,
            borderRadius: BorderRadius.circular(sudut),
            child: InkWell(
              borderRadius: BorderRadius.circular(sudut),
              onTap: () => onPilih(ikon),
              child: SizedBox(
                width: ukuran,
                height: ukuran,
                child: Icon(
                  ikon,
                  size: ukuranIkon,
                  color: ikon == terpilih ? Colors.white : WarnaTeras.teksPudar,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
