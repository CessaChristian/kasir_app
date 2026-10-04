import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Tombol tambah kotak oranye (desain: 48×48, sudut 8), biasanya di pojok
/// kanan bawah halaman.
class TombolTambah extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const TombolTambah({super.key, required this.onTap, this.tooltip = 'Tambah'});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: WarnaTeras.oranye,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: WarnaTeras.oranye.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.add_rounded, size: 34, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
