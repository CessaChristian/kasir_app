import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Kartu putih bersudut 16 — wadah dasar hampir semua isi halaman di desain.
class KartuTeras extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const KartuTeras({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// Garis pemisah tipis di dalam kartu.
class GarisTeras extends StatelessWidget {
  final double jarak;

  const GarisTeras({super.key, this.jarak = 14});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: WarnaTeras.garis,
      margin: EdgeInsets.symmetric(vertical: jarak),
    );
  }
}
