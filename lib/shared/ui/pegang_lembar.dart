import 'package:flutter/material.dart';

/// Garis pegangan di puncak lembar bawah (desain: 108×4, gelap). Ketuk untuk
/// menutup lembar, seperti di desain.
class PegangLembar extends StatelessWidget {
  final VoidCallback? onTap;

  const PegangLembar({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Center(
          child: Container(
            width: 108,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF4A4540),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
