import 'package:flutter/material.dart';

import '../../../shared/ui/tombol_berlencana.dart';
import '../models/keranjang.dart';
import '../sheets/lembar_keranjang.dart';

/// Ikon keranjang di header halaman Kasir (desain) dengan jumlah item merah.
class TombolKeranjang extends StatelessWidget {
  final Keranjang keranjang;

  const TombolKeranjang({super.key, required this.keranjang});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: keranjang,
      builder: (context, _) => TombolBerlencana(
        ikon: Icons.shopping_cart_rounded,
        tooltip: 'Keranjang',
        jumlah: keranjang.baris.fold<int>(0, (s, b) => s + b.qty),
        onTap: () => bukaKeranjang(context, keranjang),
      ),
    );
  }
}
