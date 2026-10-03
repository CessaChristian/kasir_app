import 'package:flutter/material.dart';

import 'bingkai_halaman.dart';
import 'warna_teras.dart';

/// Kerangka halaman turunan (dibuka dari menu, bukan tab): header dengan
/// tombol kembali, tanpa nav bawah.
class HalamanTurunan extends StatelessWidget {
  final String judul;
  final Widget child;

  const HalamanTurunan({super.key, required this.judul, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarnaTeras.latar,
      body: SafeArea(
        child: BingkaiHalaman(
          judul: judul,
          onKembali: () => Navigator.of(context).maybePop(),
          child: child,
        ),
      ),
    );
  }
}
