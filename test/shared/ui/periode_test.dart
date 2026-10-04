import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/periode/bagian_filter.dart';
import 'package:kasir_app/shared/ui/periode/kartu_periode.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';

/// Filter periode bersama (Pengeluaran, nanti Riwayat/Laporan/Riwayat Shift).
void main() {
  final hariIni = DateTime(2026, 10, 4, 15, 30); // Minggu

  test('pintasan mengikuti desain dan hari ini dihitung dari tanggalnya', () {
    final p = {for (final (n, q) in pintasanPeriode(hariIni)) n: q};
    expect(p.keys, [
      'Hari ini',
      'Kemarin',
      '7 Hari Terakhir',
      '30 Hari Terakhir',
      'Bulan Ini',
      'Bulan Lalu',
    ]);
    expect(p['Hari ini'], Periode.hari(DateTime(2026, 10, 4)));
    expect(p['Kemarin'], Periode.hari(DateTime(2026, 10, 3)));
    expect(
      p['7 Hari Terakhir'],
      Periode(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
    );
    expect(p['30 Hari Terakhir']!.dari, DateTime(2026, 9, 5));
    expect(
      p['Bulan Ini'],
      Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 4)),
    );
    expect(
      p['Bulan Lalu'],
      Periode(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
    );
  });

  test('Bulan Lalu di bulan Januari mundur ke Desember tahun lalu', () {
    final p = pintasanPeriode(DateTime(2027, 1, 10)).last.$2;
    expect(p, Periode(DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
  });

  test('nama periode: pintasan dikenali, selain itu "Filter periode"', () {
    expect(namaPeriode(Periode.hari(hariIni), hariIni), 'Hari ini');
    expect(
      namaPeriode(
        Periode(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        hariIni,
      ),
      'Bulan Lalu',
    );
    expect(
      namaPeriode(
        Periode(DateTime(2026, 9, 2), DateTime(2026, 9, 30)),
        hariIni,
      ),
      'Filter periode',
    );
  });

  test('label tanggal mengikuti format desain', () {
    expect(labelPeriode(Periode.hari(DateTime(2026, 10, 1))), '1 Okt 2026');
    expect(
      labelPeriode(Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 7))),
      '1 – 7 Okt 2026',
    );
    expect(
      labelPeriode(Periode(DateTime(2026, 9, 28), DateTime(2026, 10, 4))),
      '28 Sep – 4 Okt 2026',
    );
    expect(
      labelPeriode(Periode(DateTime(2025, 12, 28), DateTime(2026, 1, 3))),
      '28 Des 2025 – 3 Jan 2026',
    );
  });

  test('jam diabaikan, dan batas akhir eksklusif = esok hari pukul 00.00', () {
    final p = Periode(DateTime(2026, 10, 1, 23, 59), DateTime(2026, 10, 3, 1));
    expect(p.dari, DateTime(2026, 10, 1));
    expect(p.batasAkhir, DateTime(2026, 10, 4));
  });

  test('rentang bulan dipotong di hari ini — tidak ada data masa depan', () {
    expect(
      periodeBulan(DateTime(2026, 9), DateTime(2026, 10), hariIni),
      Periode(DateTime(2026, 9, 1), DateTime(2026, 10, 4)),
    );
    expect(
      periodeBulan(DateTime(2026, 2), DateTime(2026, 2), hariIni),
      Periode(DateTime(2026, 2, 1), DateTime(2026, 2, 28)),
    );
  });

  testWidgets(
    'kartu filter Pengeluaran: nama + kategori, lembar dan Terapkan',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      const bagian = BagianFilter(
        judulLembar: 'Filter Pengeluaran',
        judul: 'Kategori biaya',
        lebarSama: false,
        opsi: [
          OpsiFilter(kode: null, label: 'Semua'),
          OpsiFilter(kode: 'asset', label: 'Asset'),
          OpsiFilter(kode: 'bahan_baku', label: 'Bahan Baku'),
        ],
      );
      final hariIni = DateTime(2026, 10, 4);
      var periode = Periode.hari(hariIni);
      String? kategori;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, ulang) => KartuPeriode(
                periode: periode,
                bagian: bagian,
                pilihan: kategori,
                hariIni: hariIni,
                onBerubah: (p) => ulang(() => periode = p),
                onBerubahPilihan: (k) => ulang(() => kategori = k),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hari ini'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);

      await t.tap(find.text('Ubah'));
      await t.pumpAndSettle();
      expect(find.text('Filter Pengeluaran'), findsOneWidget);
      expect(find.text('Kategori biaya'), findsOneWidget);
      await t.tap(find.text('Bahan Baku'));
      await t.pump();
      await t.tap(find.text('Terapkan'));
      await t.pumpAndSettle();

      expect(kategori, 'bahan_baku');
      expect(find.text('Hari ini · Bahan Baku'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget, reason: 'bukan bawaan lagi');

      await t.tap(find.text('Reset'));
      await t.pump();
      expect(kategori, isNull);
      await t.pumpAndSettle(const Duration(seconds: 3));
    },
  );
}
