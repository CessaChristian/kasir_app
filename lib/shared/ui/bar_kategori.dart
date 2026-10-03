import 'package:flutter/material.dart';

import '../../utils/currency_formatter.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// Satu baris "label · nominal" dengan bar porsi di bawahnya.
class BarKategori extends StatelessWidget {
  final String label;
  final int nilai;
  final int total;
  final Color warna;

  const BarKategori({
    super.key,
    required this.label,
    required this.nilai,
    required this.total,
    this.warna = WarnaTeras.merahBar,
  });

  @override
  Widget build(BuildContext context) {
    final porsi = total == 0 ? 0.0 : nilai / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  color: WarnaTeras.teks,
                ),
              ),
            ),
            Text(
              formatRp(nilai),
              style: const TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.teks,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: porsi),
            duration: const Duration(milliseconds: 400),
            curve: const Cubic(.3, .7, 0, 1),
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              color: warna,
              backgroundColor: WarnaTeras.latarAbu,
            ),
          ),
        ),
      ],
    );
  }
}
