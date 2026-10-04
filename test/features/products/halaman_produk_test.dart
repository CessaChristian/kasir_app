import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/products/sheets/product_form_sheet.dart';
import 'package:kasir_app/features/products/widgets/baris_produk.dart';
import 'package:kasir_app/features/sales/models/pilihan_produk.dart';
import 'package:kasir_app/shared/ui/lembar_konfirmasi.dart';

/// Halaman Produk mengikuti desain baru.
void main() {
  Product produk({bool pedas = false, bool manis = false, bool es = false}) =>
      Product(
        id: 'p1',
        name: 'Kopi Susu',
        price: 15000,
        hasSpicyOption: pedas,
        hasSweetOption: manis,
        hasIceOption: es,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        syncStatus: 'synced',
      );

  group('teksRingkasPilihan', () {
    test('satu kelompok = "Level ...", lebih = "N varian", tanpa = kosong', () {
      expect(teksRingkasPilihan(const []), '');
      expect(teksRingkasPilihan(const [KelompokPilihan.pedas]), 'Level pedas');
      expect(teksRingkasPilihan(const [KelompokPilihan.es]), 'Level es');
      expect(
        teksRingkasPilihan(const [KelompokPilihan.manis, KelompokPilihan.es]),
        '2 varian',
      );
    });
  });

  group('galatFormProduk', () {
    test('nama kosong, harga kosong/nol, lalu sah', () {
      expect(
        galatFormProduk(nama: '  ', hargaTeks: '15.000'),
        'Nama produk wajib diisi',
      );
      expect(galatFormProduk(nama: 'Kopi', hargaTeks: ''), 'Harga wajib diisi');
      expect(
        galatFormProduk(nama: 'Kopi', hargaTeks: '0'),
        'Harga wajib diisi',
      );
      expect(galatFormProduk(nama: 'Kopi', hargaTeks: '15.000'), isNull);
    });
  });

  testWidgets('baris produk: kategori, ringkasan pilihan, edit & hapus', (
    t,
  ) async {
    var edit = 0, hapus = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarisProduk(
            produk: produk(manis: true, es: true),
            namaKategori: 'Tanpa Kategori',
            ikonKategori: Icons.block_rounded,
            onEdit: () => edit++,
            onHapus: () => hapus++,
          ),
        ),
      ),
    );
    expect(find.text('Kopi Susu'), findsOneWidget);
    expect(find.text('Rp 15.000'), findsOneWidget);
    expect(find.text('Tanpa Kategori'), findsOneWidget);
    expect(find.text('2 varian'), findsOneWidget);

    await t.tap(find.text('Kopi Susu'));
    await t.tap(find.byIcon(Icons.delete_outline_rounded));
    expect(
      (edit, hapus),
      (1, 1),
      reason: 'ketuk baris = edit; tombol merah = hapus, bukan edit',
    );
  });

  testWidgets('baris tanpa pilihan tidak menampilkan ringkasan', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarisProduk(
            produk: produk(),
            namaKategori: 'Kopi',
            ikonKategori: Icons.coffee_rounded,
            onEdit: () {},
            onHapus: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('varian'), findsNothing);
    expect(find.textContaining('Level'), findsNothing);
  });

  testWidgets('lembar konfirmasi: Batal = false, aksi = true', (t) async {
    final hasil = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => hasil.add(
              await tampilkanLembarKonfirmasi(
                context,
                ikon: Icons.delete_outline_rounded,
                judul: 'Hapus produk?',
                catatan:
                    'Kopi Susu akan dihapus dari daftar produk dan halaman kasir.',
                labelAksi: 'Hapus',
              ),
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    );
    for (final tombol in ['Batal', 'Hapus']) {
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      expect(find.text('Hapus produk?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, tombol));
      await t.pumpAndSettle();
    }
    expect(hasil, [false, true]);
  });
}
