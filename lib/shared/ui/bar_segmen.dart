import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Bar tipis berisi beberapa potongan sebanding nilainya, mis. Tunai vs QRIS
/// atau Dine In vs Delivery di Laporan. Kalau semuanya nol, bar abu polos.
class BarSegmen extends StatelessWidget {
  final List<(int, Color)> isi;
  final double tinggi;

  /// Celah antar-potongan (desain Tipe Pesanan: 2).
  final double celah;

  const BarSegmen({
    super.key,
    required this.isi,
    this.tinggi = 10,
    this.celah = 0,
  });

  @override
  Widget build(BuildContext context) {
    final ada = [
      for (final (nilai, warna) in isi)
        if (nilai > 0) (nilai, warna),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(tinggi / 2),
      child: SizedBox(
        height: tinggi,
        child: ada.isEmpty
            ? const ColoredBox(color: WarnaTeras.latarAbu)
            : Row(
                children: [
                  for (var i = 0; i < ada.length; i++) ...[
                    if (i > 0) SizedBox(width: celah),
                    Expanded(
                      flex: ada[i].$1,
                      child: ColoredBox(color: ada[i].$2),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
