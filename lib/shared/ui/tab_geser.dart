import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Tab dua pilihan dengan latar putih yang bergeser (desain), mis.
/// "Tanggal | Bulan" di lembar periode atau "Transaksi | Pengeluaran" di
/// Detail Shift.
class TabGeser extends StatelessWidget {
  final List<String> pilihan;
  final int terpilih;
  final ValueChanged<int> onPilih;
  final Color latar;
  final double tinggi;
  final double sudut;

  const TabGeser({
    super.key,
    required this.pilihan,
    required this.terpilih,
    required this.onPilih,
    this.latar = WarnaTeras.latarAbu,
    this.tinggi = 38,
    this.sudut = 10,
  });

  @override
  Widget build(BuildContext context) {
    final n = pilihan.length;
    return Container(
      height: tinggi,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(sudut),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: const Cubic(.32, .72, 0, 1),
            // -1 = paling kiri, 1 = paling kanan.
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * terpilih / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: WarnaTeras.kartu,
                  borderRadius: BorderRadius.circular(sudut - 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3C230A).withValues(alpha: 0.12),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPilih(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w600,
                          color: i == terpilih
                              ? WarnaTeras.teks
                              : WarnaTeras.teksPudar,
                        ),
                        child: Text(
                          pilihan[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
