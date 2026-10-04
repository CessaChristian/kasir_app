import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Kelompok per hari dengan pita oranye yang bisa dilipat (desain Riwayat):
/// ikon kalender · tanggal + jumlah · total · panah. Isinya di kotak putih
/// di bawah pita.
class PitaHari extends StatelessWidget {
  final String judul;
  final String keterangan;
  final String total;
  final bool terbuka;
  final VoidCallback onTap;
  final List<Widget> isi;

  const PitaHari({
    super.key,
    required this.judul,
    required this.keterangan,
    required this.total,
    required this.terbuka,
    required this.onTap,
    required this.isi,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: WarnaTeras.oranye,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          child: InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            judul,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: TeksTeras.biasa,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            keterangan,
                            style: const TextStyle(
                              fontSize: TeksTeras.kecil,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      total,
                      style: const TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: terbuka ? 0 : 0.5,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.expand_less_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: terbuka
              ? ColoredBox(
                  color: WarnaTeras.kartu,
                  child: Column(children: isi),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
