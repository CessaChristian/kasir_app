import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/report/models/ringkasan_laporan.dart';
import 'package:kasir_app/features/report/pages/laporan_page.dart';
import 'package:kasir_app/shared/ui/nav_bawah_teras.dart';
import 'package:kasir_app/shared/ui/segarkan/pengendali_segarkan.dart';
import 'package:kasir_app/shared/ui/segarkan/tombol_segarkan.dart';

/// Audit 6 Nov nomor 53.
void main() {
  testWidgets('tombol Kasir: bagian atas lingkaran yang menyembul bisa '
      'diketuk', (t) async {
    final dipilih = <int>[];
    const item = ItemNav(
      ikon: Icons.circle_outlined,
      ikonAktif: Icons.circle,
      label: 'x',
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: NavBawahTeras(
          kiri: const [item, item],
          tengah: const ItemNav(
            ikon: Icons.point_of_sale_outlined,
            ikonAktif: Icons.point_of_sale,
            label: 'Kasir',
          ),
          kanan: const [item, item],
          terpilih: 0,
          onPilih: dipilih.add,
        ),
      ),
    ));
    // Ikon di tengah lingkaran (garis tengah 60): 25 px di atasnya masih
    // di dalam lingkaran, di bagian yang menyembul.
    final ikon = t.getCenter(find.byIcon(Icons.point_of_sale_outlined));
    await t.tapAt(Offset(ikon.dx, ikon.dy - 25));
    await t.pump();
    expect(dipilih, [2]);
  });

  testWidgets('tes alur 10 Nov: layar kecil + huruf besar, label tidak menempel',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ItemNav nav(String label) => ItemNav(
          ikon: Icons.circle_outlined,
          ikonAktif: Icons.circle,
          label: label,
        );
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: NavBawahTeras(
          kiri: [nav('Dashboard'), nav('Pengeluaran')],
          tengah: nav('Kasir'),
          kanan: [nav('Riwayat'), nav('Profil')],
          terpilih: 0,
          onPilih: (_) {},
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    final dasbor = t.getRect(find.text('Dashboard'));
    final keluar = t.getRect(find.text('Pengeluaran'));
    expect(dasbor.right, lessThanOrEqualTo(keluar.left - 2),
        reason: 'ada celah di antara dua label');
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('ikon segarkan tidak berputar tanpa sinkron', (t) async {
    final sinkron = Completer<HasilSync>();
    final p = PengendaliSegarkan(
      jalankan: () => sinkron.future,
      lamaHasil: const Duration(milliseconds: 100),
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: TombolSegarkan(pengendali: p)),
    ));
    AnimationController putar() => t
        .widget<RotationTransition>(find.descendant(
          of: find.byType(TombolSegarkan),
          matching: find.byType(RotationTransition),
        ))
        .turns as AnimationController;

    unawaited(p.segarkan());
    await t.pump();
    expect(putar().isAnimating, isTrue, reason: 'sinkron berjalan');
    sinkron.complete(const HasilSync());
    await t.pump();
    // Putaran terakhir diselesaikan, lalu berhenti.
    await t.pump(const Duration(seconds: 1));
    expect(putar().isAnimating, isFalse);

    // Pita hasil menutup (kabar tanpa sinkron baru): ikon tetap diam.
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 50));
    expect(putar().isAnimating, isFalse);
    await t.pump(const Duration(seconds: 2));
  });

  test('batang grafik yang dipilih diingat lewat namanya', () {
    const jam9 = BatangGrafik('09', 10, nama: 'Jam 09:00');
    const jam10 = BatangGrafik('', 20, nama: 'Jam 10:00');
    const jam8 = BatangGrafik('08', 5, nama: 'Jam 08:00');
    expect(indeksBatang(const [jam9, jam10], 'Jam 10:00'), 1);
    // Sinkron membawa shift yang dibuka lebih pagi: batang 08 muncul di
    // depan, sorotan tetap di jam 10.
    expect(indeksBatang(const [jam8, jam9, jam10], 'Jam 10:00'), 2);
    expect(indeksBatang(const [jam8, jam9], 'Jam 10:00'), isNull);
  });
}
