import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Chip status berbintik (desain): "● Aktif" hijau atau "● Selesai" abu.
class ChipStatus extends StatelessWidget {
  final String label;
  final bool aktif;

  const ChipStatus({super.key, required this.label, required this.aktif});

  static const _abu = Color(0xFF6B6058);
  static const _latarAbu = Color(0xFFF1ECE7);

  @override
  Widget build(BuildContext context) {
    final warna = aktif ? WarnaTeras.hijau : _abu;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: aktif ? WarnaTeras.hijauMuda : _latarAbu,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: warna, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w600,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}
