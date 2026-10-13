import 'package:flutter/material.dart';

import '../../../shared/ui/warna_teras.dart';
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
      builder: (context, _) {
        final jumlah = keranjang.baris.fold<int>(0, (s, b) => s + b.qty);
        return Tooltip(
          message: 'Keranjang',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => bukaKeranjang(context, keranjang),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(
                      Icons.shopping_cart_rounded,
                      size: 25,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                  if (jumlah > 0)
                    Positioned(
                      top: 2,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 19),
                        height: 19,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: WarnaTeras.merah,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: WarnaTeras.latar, width: 2),
                        ),
                        child: Text(
                          '$jumlah',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
