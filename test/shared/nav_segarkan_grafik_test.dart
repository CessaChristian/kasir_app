import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/report/models/ringkasan_laporan.dart';
import 'package:kasir_app/features/report/pages/laporan_page.dart';
import 'package:kasir_app/shared/ui/nav_bawah_teras.dart';
import 'package:kasir_app/shared/ui/teks_teras.dart';
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

  group('tes alur 10 Nov: label nav seragam di layar mana pun', () {
    ItemNav nav(String label) => ItemNav(
          ikon: Icons.circle_outlined,
          ikonAktif: Icons.circle,
          label: label,
        );
    const label = ['Dashboard', 'Pengeluaran', 'Produk', 'Riwayat', 'Profil'];

    Future<void> pasang(
      WidgetTester t,
      Size layar,
      double rasio, {
      double huruf = 1,
    }) async {
      t.view.physicalSize = layar;
      t.view.devicePixelRatio = rasio;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(huruf)),
          child: child!,
        ),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NavBawahTeras(
            kiri: [nav(label[0]), nav(label[1])],
            tengah: nav(label[2]),
            kanan: [nav(label[3]), nav(label[4])],
            terpilih: 0,
            onPilih: (_) {},
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    }

    void cekSeragam(WidgetTester t) {
      final ukuran = {
        for (final l in label)
          t.widget<Text>(find.text(l)).style!.fontSize,
      };
      expect(ukuran, hasLength(1),
          reason: 'semua label satu ukuran huruf — dulu label panjang '
              'mengecil sendiri');
      final tinggi = {
        for (final l in label) t.getRect(find.text(l)).height,
      };
      expect(tinggi, hasLength(1));
      final bawah = {
        for (final l in label) t.getRect(find.text(l)).bottom,
      };
      expect(bawah, hasLength(1),
          reason: 'semua label di garis bawah yang sama, termasuk label tengah');
      for (var i = 0; i + 1 < label.length; i++) {
        final kiri = t.getRect(find.text(label[i]));
        final kanan = t.getRect(find.text(label[i + 1]));
        expect(kiri.right, lessThanOrEqualTo(kanan.left - 2),
            reason: '${label[i]} tidak menempel ke ${label[i + 1]}');
      }
    }

    for (final (nama, layar, rasio, huruf) in [
      ('HP 1080 px, kerapatan 420', const Size(1080, 2400), 420 / 160, 1.0),
      ('HP 1080 px, kerapatan 440', const Size(1080, 2400), 440 / 160, 1.0),
      ('HP 720 px, huruf 130%', const Size(720, 1440), 2.0, 1.3),
      ('layar 320 px, huruf 130%', const Size(320, 640), 1.0, 1.3),
    ]) {
      testWidgets(nama, (t) async {
        await pasang(t, layar, rasio, huruf: huruf);
        cekSeragam(t);
      });
    }

    testWidgets('layar lebar: ukuran desain, tidak dikecilkan', (t) async {
      await pasang(t, const Size(1600, 2400), 2.0);
      expect(t.widget<Text>(find.text('Pengeluaran')).style!.fontSize,
          TeksTeras.kecil);
    });
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
