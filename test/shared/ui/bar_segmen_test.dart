import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/bar_segmen.dart';
import 'package:kasir_app/shared/ui/warna_teras.dart';

/// Bar persentase Laporan (Metode Pembayaran, Tipe Pesanan). Dulu potongan
/// warnanya setinggi 0 — barnya tak terlihat, kartu tinggal bercelah kosong
/// di atas (temuan di HP 2026-10-17).
void main() {
  Future<List<Size>> potongan(WidgetTester t, BarSegmen bar) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: Column(children: [bar])),
          ),
        ),
      ),
    );
    return [
      for (final e in find
          .descendant(
            of: find.byType(BarSegmen),
            matching: find.byType(ColoredBox),
          )
          .evaluate())
        t.getSize(find.byWidget(e.widget)),
    ];
  }

  testWidgets('potongan terlihat: setinggi bar, lebar sesuai porsi', (t) async {
    final p = await potongan(
      t,
      const BarSegmen(isi: [(3, Colors.green), (1, Colors.blue)]),
    );
    expect(p, hasLength(2));
    expect(p[0], const Size(225, 10));
    expect(p[1], const Size(75, 10));
  });

  testWidgets('celah di antara potongan', (t) async {
    final p = await potongan(
      t,
      const BarSegmen(celah: 2, isi: [(1, Colors.green), (1, Colors.blue)]),
    );
    expect(p.map((s) => s.width), [149, 149]);
    expect(p.every((s) => s.height == 10), isTrue);
  });

  testWidgets('semua nol: bar abu selebar penuh', (t) async {
    final p = await potongan(t, const BarSegmen(isi: [(0, Colors.green)]));
    expect(p.single, const Size(300, 10));
    final kotak = t.widget<ColoredBox>(
      find.descendant(
        of: find.byType(BarSegmen),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(kotak.color, WarnaTeras.latarAbu);
  });
}
