import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Tombol oranye muda selebar kartu, mis. "Lihat Riwayat Shift ›".
class TombolLembut extends StatelessWidget {
  final IconData ikon;
  final String label;
  final VoidCallback onTap;

  const TombolLembut({
    super.key,
    required this.ikon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WarnaTeras.oranyeMuda,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ikon, size: 18, color: WarnaTeras.oranye),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WarnaTeras.oranye,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: WarnaTeras.oranye,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
