import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/report/models/ringkasan_laporan.dart';
import 'package:kasir_app/features/report/services/dokumen_laporan.dart';
import 'package:kasir_app/features/report/services/ekspor_laporan.dart';
import 'package:kasir_app/features/report/services/pdf_laporan.dart';
import 'package:kasir_app/features/report/widgets/lembar_unduh_laporan.dart';
import 'package:kasir_app/shared/services/simpan_berkas.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:pdf/widgets.dart' as pw;

/// Unduh Laporan: isi PDF dan Excel sama dengan layar, Excel berisi angka,
/// lembar pilih format dan "Laporan siap", serta simpan ke folder Download.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  final hari = DateTime(2026, 10, 1);
  DateTime jam(int h) => DateTime(2026, 10, 1, h);

  Transaction trx(String id, int h, int total, {bool batal = false}) =>
      Transaction(
        id: id,
        invoiceNo: 'TRX/$id',
        createdAt: jam(h),
        total: total,
        paymentMethod: id == 'b' ? 'qris' : 'cash',
        cashierUserId: 'budi',
        orderType: 'dine_in',
        updatedAt: jam(h),
        deletedAt: batal ? jam(h + 1) : null,
        cancelledByUserId: batal ? 'owner' : null,
        cancelReason: batal ? 'Pelanggan batal' : null,
        syncStatus: 'synced',
      );

  TransactionItem item(String tx, int qty, int harga) => TransactionItem(
    id: 'i-$tx',
    transactionId: tx,
    productId: 'p1',
    productName: 'Nasi Goreng',
    qty: qty,
    priceAtSale: harga,
    subtotal: qty * harga,
    notes: 'Pedas: Sedang',
    createdAt: hari,
    updatedAt: hari,
    syncStatus: 'synced',
  );

  Expense belanja(String id, int nominal, {bool batal = false}) => Expense(
    id: id,
    shiftId: 's',
    userId: 'budi',
    description: 'Es batu',
    amount: nominal,
    category: 'bahan_baku',
    qty: 1,
    createdAt: jam(10),
    updatedAt: jam(10),
    deletedAt: batal ? jam(11) : null,
    cancelledByUserId: batal ? 'owner' : null,
    syncStatus: 'synced',
  );

  final periode = Periode.hari(hari);
  final r = ringkasLaporan(
    periode: periode,
    transaksi: [
      trx('a', 9, 30000),
      trx('b', 10, 20000),
      trx('x', 11, 99000, batal: true),
    ],
    item: {
      'a': [item('a', 2, 15000)],
      'b': [item('b', 1, 20000)],
    },
    pengeluaran: [belanja('e1', 7000), belanja('e2', 5000, batal: true)],
    shift: [
      Shift(
        id: 's',
        userId: 'budi',
        startAt: jam(8),
        endAt: jam(12),
        updatedAt: jam(8),
        syncStatus: 'synced',
      ),
    ],
    produk: const [],
    kategori: const [],
    sekarang: jam(23),
  );
  const nama = {'budi': 'budi', 'owner': 'owner'};

  DokumenLaporan dokumen({required bool denganPengeluaran}) =>
      susunDokumenLaporan(
        namaToko: 'Teras Inn',
        periode: periode,
        r: r,
        nama: nama,
        denganPengeluaran: denganPengeluaran,
        dibuat: DateTime(2026, 10, 1, 23, 5),
        olehNama: 'owner',
      );

  group('isi dokumen', () {
    test('owner: 8 bagian sesuai urutan', () {
      final d = dokumen(denganPengeluaran: true);
      expect(d.tabel.map((t) => t.judul), [
        'Ringkasan',
        'Per Jam',
        'Produk',
        'Kategori',
        'Transaksi',
        'Rincian Item',
        'Pengeluaran',
        'Dibatalkan',
      ]);
    });

    test('kasir tanpa izin pengeluaran: tidak ada jejak pengeluaran', () {
      final d = dokumen(denganPengeluaran: false);
      expect(d.tabel.map((t) => t.judul), isNot(contains('Pengeluaran')));
      final semuaTeks = [
        for (final t in d.tabel) ...[
          ...t.kolom,
          for (final b in t.baris)
            for (final s in b)
              if (s is SelTeks) s.teks,
        ],
      ];
      expect(
        semuaTeks.where((x) => x.toLowerCase().contains('pengeluaran')),
        isEmpty,
      );
      expect(semuaTeks.where((x) => x.toLowerCase().contains('laba')), isEmpty);
    });

    test('angka sama dengan layar', () {
      final d = dokumen(denganPengeluaran: true);
      final transaksi = d.tabel.firstWhere((t) => t.judul == 'Transaksi');
      final total = transaksi.baris.fold<int>(
        0,
        (s, b) => s + (b.last as SelRupiah).nilai,
      );
      expect(total, r.pendapatan, reason: 'yang dibatalkan tidak ikut');
      expect(transaksi.baris, hasLength(2));

      final perJam = d.tabel[1];
      // Hanya jam yang ada isinya: 09 (transaksi) dan 10 (transaksi +
      // pengeluaran). Jam 11 hanya berisi transaksi batal — kosong.
      expect(
        [for (final b in perJam.baris) (b.first as SelTeks).teks],
        ['09:00 – 09:59', '10:00 – 10:59'],
      );

      final batal = d.tabel.last;
      expect(batal.baris, hasLength(2), reason: 'transaksi dan pengeluaran');
      expect((batal.baris.first.last as SelTeks).teks, 'Pelanggan batal');

      final item = d.tabel.firstWhere((t) => t.judul == 'Rincian Item');
      expect((item.baris.first[3] as SelTeks).teks, 'Pedas: Sedang');
    });

    RingkasanLaporan rentang(Periode p, List<DateTime> waktu) => ringkasLaporan(
      periode: p,
      transaksi: [
        for (var i = 0; i < waktu.length; i++)
          Transaction(
            id: 'w$i',
            invoiceNo: 'TRX/w$i',
            createdAt: waktu[i],
            total: 10000,
            paymentMethod: 'cash',
            orderType: 'dine_in',
            updatedAt: waktu[i],
            syncStatus: 'synced',
          ),
      ],
      item: const {},
      pengeluaran: const [],
      shift: const [],
      produk: const [],
      kategori: const [],
      sekarang: DateTime(2027),
    );

    test('per hari: hari tanpa isi tidak dimasukkan', () {
      final p = Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 10));
      final r = rentang(p, [
        DateTime(2026, 10, 2, 9),
        DateTime(2026, 10, 7, 9),
      ]);
      expect(
        [for (final w in r.perWaktu) w.label],
        ['Jumat, 2 Okt 2026', 'Rabu, 7 Okt 2026'],
      );
    });

    test('lebih dari 31 hari: per bulan, total tebal lalu harinya', () {
      final p = Periode(DateTime(2026, 7, 1), DateTime(2026, 9, 30));
      final r = rentang(p, [
        DateTime(2026, 7, 3, 9),
        DateTime(2026, 7, 3, 12),
        DateTime(2026, 9, 20, 9),
      ]);
      expect(
        [for (final w in r.perWaktu) (w.label, w.totalBulan, w.pendapatan)],
        [
          ('Juli 2026', true, 20000),
          ('Jumat, 3 Jul 2026', false, 20000),
          // Agustus kosong sama sekali: tidak ada baris.
          ('September 2026', true, 10000),
          ('Minggu, 20 Sep 2026', false, 10000),
        ],
      );
      final d = susunDokumenLaporan(
        namaToko: 'Teras Inn',
        periode: p,
        r: r,
        nama: const {},
        denganPengeluaran: true,
        dibuat: DateTime(2026, 10, 1),
        olehNama: 'owner',
      );
      expect(d.tabel[1].judul, 'Per Bulan');
      expect(d.tabel[1].barisTebal, {0, 2});

      final excel = Excel.decodeBytes(buatExcelLaporan(d));
      final perBulan = excel.tables['Per Bulan']!;
      expect(perBulan.rows[5][0]!.cellStyle!.isBold, isTrue);
      expect(perBulan.rows[6][0]!.cellStyle?.isBold ?? false, isFalse);
    });

    group('kelompok Transaksi & Rincian Item', () {
      Transaction t(String id, DateTime w, int total) => Transaction(
        id: id,
        invoiceNo: 'TRX/$id',
        createdAt: w,
        total: total,
        paymentMethod: 'cash',
        orderType: 'dine_in',
        updatedAt: w,
        syncStatus: 'synced',
      );
      List<(String?, int)> ringkas(Periode p, List<Transaction> l) => [
        for (final k in kelompokkanTransaksi(p, l))
          (k.judul, k.transaksi.length),
      ];

      test('1 hari: tanpa kelompok', () {
        expect(
          ringkas(Periode.hari(DateTime(2026, 7, 1)), [
            t('a', DateTime(2026, 7, 1, 9), 1),
          ]),
          [(null, 1)],
        );
      });

      test('2–7 hari: per hari, hari kosong tidak dibuat', () {
        expect(
          ringkas(Periode(DateTime(2026, 7, 6), DateTime(2026, 7, 12)), [
            t('a', DateTime(2026, 7, 6, 9), 1),
            t('b', DateTime(2026, 7, 6, 14), 1),
            t('c', DateTime(2026, 7, 9, 9), 1),
          ]),
          [('Senin, 6 Jul 2026', 2), ('Kamis, 9 Jul 2026', 1)],
        );
      });

      test('8–31 hari: blok 7 hari dari awal periode', () {
        expect(
          ringkas(Periode(DateTime(2026, 7, 1), DateTime(2026, 7, 31)), [
            t('a', DateTime(2026, 7, 1, 9), 1),
            t('b', DateTime(2026, 7, 7, 23), 1),
            t('c', DateTime(2026, 7, 8, 9), 1),
            t('d', DateTime(2026, 7, 30, 9), 1),
          ]),
          [
            ('Minggu 1 · 1–7 Jul 2026', 2),
            ('Minggu 2 · 8–14 Jul 2026', 1),
            // Minggu 3 dan 4 kosong: tidak dibuat.
            ('Minggu 5 · 29–31 Jul 2026', 1),
          ],
        );
      });

      test('minggu yang menyeberang bulan', () {
        expect(
          ringkas(Periode(DateTime(2026, 6, 28), DateTime(2026, 7, 20)), [
            t('a', DateTime(2026, 7, 2, 9), 1),
          ]),
          [('Minggu 1 · 28 Jun – 4 Jul 2026', 1)],
        );
      });

      test('lebih dari 31 hari: per bulan', () {
        expect(
          ringkas(Periode(DateTime(2026, 1, 1), DateTime(2026, 10, 6)), [
            t('a', DateTime(2026, 6, 28, 9), 1),
            t('b', DateTime(2026, 7, 1, 9), 1),
            t('c', DateTime(2026, 7, 2, 9), 1),
          ]),
          [('Juni 2026', 1), ('Juli 2026', 2)],
        );
      });

      test('baris judul kelompok: tebal, berisi jumlah dan total', () {
        final p = Periode(DateTime(2026, 7, 1), DateTime(2026, 7, 31));
        final l = [
          t('a', DateTime(2026, 7, 1, 9), 10000),
          t('b', DateTime(2026, 7, 2, 9), 20000),
          t('c', DateTime(2026, 7, 9, 9), 5000),
        ];
        final r = ringkasLaporan(
          periode: p,
          transaksi: l.reversed.toList(),
          item: {
            for (final x in l) x.id: [item(x.id, 2, x.total ~/ 2)],
          },
          pengeluaran: const [],
          shift: const [],
          produk: const [],
          kategori: const [],
          sekarang: DateTime(2027),
        );
        final d = susunDokumenLaporan(
          namaToko: 'Teras Inn',
          periode: p,
          r: r,
          nama: const {},
          denganPengeluaran: true,
          dibuat: DateTime(2026, 8, 1),
          olehNama: 'owner',
        );
        final trx = d.tabel.firstWhere((x) => x.judul == 'Transaksi');
        expect(trx.barisTebal, {0, 3});
        expect((trx.baris[0][0] as SelTeks).teks, 'Minggu 1 · 1–7 Jul 2026');
        expect((trx.baris[0][3] as SelTeks).teks, '2 transaksi');
        expect((trx.baris[0].last as SelRupiah).nilai, 30000);

        // Jumlah semua kelompok = pendapatan.
        final totalKelompok = [
          for (final i in trx.barisTebal)
            (trx.baris[i].last as SelRupiah).nilai,
        ].fold(0, (a, b) => a + b);
        expect(totalKelompok, r.pendapatan);

        final rincian = d.tabel.firstWhere((x) => x.judul == 'Rincian Item');
        expect(rincian.barisTebal, {0, 3});
        expect((rincian.baris[0][4] as SelAngka).nilai, 4, reason: 'qty');
        expect((rincian.baris[0].last as SelRupiah).nilai, 30000);
      });
    });

    test('boleh diunduh: ada transaksi, atau pengeluaran bagi yang boleh', () {
      RingkasanLaporan hanya({
        List<Transaction> t = const [],
        List<Expense> e = const [],
      }) => ringkasLaporan(
        periode: periode,
        transaksi: t,
        item: const {},
        pengeluaran: e,
        shift: const [],
        produk: const [],
        kategori: const [],
        sekarang: jam(23),
      );
      expect(hanya().adaIsi(denganPengeluaran: true), isFalse);
      expect(
        hanya(t: [trx('a', 9, 1)]).adaIsi(denganPengeluaran: false),
        isTrue,
      );
      expect(
        hanya(
          t: [trx('x', 9, 1, batal: true)],
        ).adaIsi(denganPengeluaran: false),
        isTrue,
        reason: 'transaksi batal tetap dilaporkan',
      );
      final belanjaSaja = hanya(e: [belanja('e', 5000)]);
      expect(belanjaSaja.adaIsi(denganPengeluaran: true), isTrue);
      expect(
        belanjaSaja.adaIsi(denganPengeluaran: false),
        isFalse,
        reason: 'kasir tanpa izin pengeluaran: file-nya kosong',
      );
    });

    test('nama file dan label periode (desain)', () {
      expect(dokumen(denganPengeluaran: true).namaFile, 'Laporan_01102026');
      expect(dokumen(denganPengeluaran: true).labelPeriode, '01/10/2026');
      final rentang = Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 5));
      expect(labelPeriodeUnduhan(rentang), '01/10/2026 – 05/10/2026');
    });

    test('ukuran berkas', () {
      expect(ukuranBerkas(253952), '248 KB');
      expect(ukuranBerkas(1258291), '1,2 MB');
    });
  });

  test('Excel: satu lembar per bagian, nominal berupa ANGKA', () {
    final bita = buatExcelLaporan(dokumen(denganPengeluaran: true));
    final excel = Excel.decodeBytes(bita);
    expect(excel.tables.keys, isNot(contains('Sheet1')));
    expect(excel.tables.keys, contains('Rincian Item'));

    final ringkasan = excel.tables['Ringkasan']!;
    // Baris 0–2 judul, 4 kepala tabel, 5 = Pendapatan.
    expect(ringkasan.rows[5][0]!.value, TextCellValue('Pendapatan'));
    expect(ringkasan.rows[5][2]!.value, IntCellValue(50000));
    expect(ringkasan.rows[0][0]!.value.toString(), contains('Teras Inn'));
  });

  Future<BahanPdf> bahanDariBerkas() async {
    Future<pw.Font> huruf(String n) async => pw.Font.ttf(
      (await File('assets/fonts/$n').readAsBytes()).buffer.asByteData(),
    );
    return BahanPdf(
      biasa: await huruf('Roboto-Regular.ttf'),
      tebal: await huruf('Roboto-Bold.ttf'),
      logo: await File('assets/images/Logo Teras Inn.png').readAsBytes(),
    );
  }

  test('PDF: berkas sah', () async {
    final bita = await buatPdfLaporan(
      dokumen(denganPengeluaran: true),
      await bahanDariBerkas(),
    );
    expect(String.fromCharCodes(bita.take(5)), '%PDF-');
    expect(bita.length, greaterThan(1000));
  });

  test(
    'PDF periode panjang: lebih dari 20 halaman, cepat, logo sekali',
    () async {
      // Dulu gagal "TooManyPagesException" (batas bawaan 20 halaman), dan satu
      // tabel raksasa membuat 3.000 transaksi butuh 16 detik.
      final awal = DateTime(2026, 1, 1);
      final banyak = [
        for (var i = 0; i < 3000; i++)
          Transaction(
            id: 'n$i',
            invoiceNo: 'TRX/$i',
            createdAt: awal.add(Duration(hours: i)),
            total: 10000,
            paymentMethod: 'cash',
            orderType: 'dine_in',
            updatedAt: awal,
            syncStatus: 'synced',
          ),
      ];
      final panjang = Periode(awal, DateTime(2026, 5, 31));
      final besar = ringkasLaporan(
        periode: panjang,
        transaksi: banyak,
        // Dua item per transaksi: tabel Rincian Item 6.000 baris — bagian
        // yang paling lambat tanpa pemotongan tabel.
        item: {
          for (final t in banyak)
            t.id: [
              for (var k = 0; k < 2; k++)
                TransactionItem(
                  id: '${t.id}-$k',
                  transactionId: t.id,
                  productId: 'p$k',
                  productName: 'Nasi Goreng Teras Spesial',
                  qty: 1,
                  priceAtSale: 5000,
                  subtotal: 5000,
                  notes: 'Pedas: Sedang',
                  createdAt: awal,
                  updatedAt: awal,
                  syncStatus: 'synced',
                ),
            ],
        },
        pengeluaran: const [],
        shift: const [],
        produk: const [],
        kategori: const [],
        sekarang: DateTime(2027),
      );
      final dok = susunDokumenLaporan(
        namaToko: 'Teras Inn',
        periode: panjang,
        r: besar,
        nama: const {},
        denganPengeluaran: true,
        dibuat: DateTime(2026, 3, 6),
        olehNama: 'owner',
      );
      final jam = Stopwatch()..start();
      final bita = await buatPdfLaporanDiLatar(dok, await bahanDariBerkas());
      jam.stop();

      final isi = String.fromCharCodes(bita);
      final halaman = RegExp(r'/Type\s*/Page[^s]').allMatches(isi).length;
      expect(halaman, greaterThan(20));
      // Tanpa pemotongan tabel: ±16 detik di Mac; dengan: ±2 detik.
      expect(jam.elapsed, lessThan(const Duration(seconds: 8)));
      expect(
        bita.length,
        lessThan(halaman * 15 * 1024),
        reason: 'logo tidak boleh tersimpan ulang di setiap halaman',
      );
    },
  );

  test('Excel di latar: sama dengan langsung', () async {
    final dok = dokumen(denganPengeluaran: true);
    final langsung = Excel.decodeBytes(buatExcelLaporan(dok));
    final latar = Excel.decodeBytes(await buatExcelLaporanDiLatar(dok));
    expect(latar.tables.keys, langsung.tables.keys);
  });

  group('lembar', () {
    testWidgets('pilih format: PDF bawaan, bisa pindah ke Excel', (t) async {
      FormatLaporan? hasil;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => hasil = await pilihFormatLaporan(
                  context,
                  labelPeriode: '01/10/2026',
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      expect(find.text('Download Laporan'), findsOneWidget);
      expect(find.text('Periode 01/10/2026'), findsOneWidget);

      await t.tap(find.text('Download'));
      await t.pumpAndSettle();
      expect(hasil, FormatLaporan.pdf, reason: 'PDF terpilih bawaan');

      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      await t.tap(find.text('Excel'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Download'));
      await t.pumpAndSettle();
      expect(hasil, FormatLaporan.excel);

      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(hasil, isNull);
    });

    testWidgets('laporan siap: kartu file, Simpan ke HP, Bagikan', (t) async {
      CaraSimpan? hasil;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => hasil = await tampilkanLaporanSiap(
                  context,
                  format: FormatLaporan.pdf,
                  namaFile: 'Laporan_01102026.pdf',
                  keterangan: 'Periode 01/10/2026 · 248 KB',
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      expect(find.text('Laporan siap'), findsOneWidget);
      expect(find.text('Laporan_01102026.pdf'), findsOneWidget);
      expect(find.text('Periode 01/10/2026 · 248 KB'), findsOneWidget);

      await t.tap(find.text('Simpan ke HP'));
      await t.pumpAndSettle();
      expect(hasil, CaraSimpan.simpanKeHp);

      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bagikan'));
      await t.pumpAndSettle();
      expect(hasil, CaraSimpan.bagikan);
    });
  });

  group('simpan ke Download', () {
    const kanal = MethodChannel('kasir_app/unduhan');
    final pesan =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => pesan.setMockMethodCallHandler(kanal, null));

    test('mengirim nama, mime, dan isi berkas', () async {
      MethodCall? diterima;
      pesan.setMockMethodCallHandler(kanal, (c) async {
        diterima = c;
        return 'content://downloads/1';
      });
      await SimpanBerkas.keDownload(
        nama: 'Laporan_01102026.pdf',
        mime: 'application/pdf',
        bita: Uint8List.fromList([1, 2, 3]),
      );
      expect(diterima!.method, 'simpanKeDownload');
      expect(diterima!.arguments['nama'], 'Laporan_01102026.pdf');
      expect(diterima!.arguments['bita'], [1, 2, 3]);
    });

    test('aplikasi versi lama (kode Android belum ada): pesan jelas', () async {
      // Tanpa penangan kanal sama sekali = MissingPluginException.
      await expectLater(
        SimpanBerkas.keDownload(
          nama: 'x.pdf',
          mime: 'application/pdf',
          bita: Uint8List(0),
        ),
        throwsA(
          isA<BerkasTidakTersimpan>().having(
            (e) => e.pesan,
            'pesan',
            contains('Pakai Bagikan'),
          ),
        ),
      );
    });

    test('Android 9 ke bawah: pesan yang bisa dimengerti', () async {
      pesan.setMockMethodCallHandler(
        kanal,
        (c) async => throw PlatformException(code: 'TIDAK_DIDUKUNG'),
      );
      await expectLater(
        SimpanBerkas.keDownload(
          nama: 'x.pdf',
          mime: 'application/pdf',
          bita: Uint8List(0),
        ),
        throwsA(
          isA<BerkasTidakTersimpan>().having(
            (e) => e.pesan,
            'pesan',
            contains('Android 10'),
          ),
        ),
      );
    });
  });
}
