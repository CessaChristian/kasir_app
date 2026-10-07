import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Sakelar 44×26 berkenop putih (desain Kelola Kasir dan Hak Akses):
/// jalur oranye saat menyala, abu saat mati.
class Sakelar extends StatelessWidget {
  final bool nilai;
  final ValueChanged<bool> onUbah;

  /// Label untuk pembaca layar.
  final String label;

  const Sakelar({
    super.key,
    required this.nilai,
    required this.onUbah,
    required this.label,
  });

  static const _mati = Color(0xFFE0D7CE);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: nilai,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onUbah(!nilai),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: nilai ? WarnaTeras.oranye : _mati,
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: nilai ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
