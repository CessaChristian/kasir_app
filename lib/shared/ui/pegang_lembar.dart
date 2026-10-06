import 'package:flutter/material.dart';

/// Garis pegangan di puncak lembar bawah (desain: 108×4, gelap). Ketuk untuk
/// menutup lembar, seperti di desain.
///
/// [PegangLembar.kecil]: varian 40×4 terang di lembar Download Laporan.
class PegangLembar extends StatelessWidget {
  final VoidCallback? onTap;
  final double lebar;
  final Color warna;

  const PegangLembar({super.key, this.onTap})
    : lebar = 108,
      warna = const Color(0xFF4A4540);

  const PegangLembar.kecil({super.key, this.onTap})
    : lebar = 40,
      warna = const Color(0xFFE0D7CE);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Center(
          child: Container(
            width: lebar,
            height: 4,
            decoration: BoxDecoration(
              color: warna,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
