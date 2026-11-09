import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/products/widgets/baris_produk.dart';

/// Audit 6 Nov nomor 59: foto produk dibuka seukuran tampilnya.
void main() {
  final asli = MemoryImage(Uint8List(0));

  test('foto 40 px di layar 3× dibuka 180 px, bukan 800', () {
    final g = gambarSeukuran(asli, lebar: 40, tinggi: 40, rasioPiksel: 3)
        as ResizeImage;
    expect(g.width, 180);
    expect(g.height, 180);
    expect(g.policy, ResizeImagePolicy.fit);
    expect(g.allowUpscaling, isFalse);
  });

  test('kartu Kasir memakai sisi terpanjangnya', () {
    final g = gambarSeukuran(asli, lebar: 170, tinggi: 140, rasioPiksel: 2)
        as ResizeImage;
    expect(g.width, 510);
  });
}
