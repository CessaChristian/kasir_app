import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/report/models/ringkasan_laporan.dart';
import 'package:kasir_app/features/report/pages/laporan_page.dart';
import 'package:kasir_app/features/report/repositories/laporan_repository.dart';
import 'package:kasir_app/features/report/widgets/grafik_batang.dart';
import 'package:kasir_app/shared/ui/periode/kartu_periode.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Laporan (desain): hitungan, grafik menurut periode, dan tampilan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  final hari = DateTime(2026, 10, 1);
  DateTime jam(int h, [int m = 0]) => DateTime(2026, 10, 1, h, m);

  Transaction trx(
    String id,
    DateTime waktu,
    int total, {
    String metode = 'cash',
    String tipe = 'dine_in',
    bool batal = false,
  }) => Transaction(
    id: id,
    invoiceNo: 'TRX/$id',
    createdAt: waktu,
    total: total,
    paymentMethod: metode,
    orderType: tipe,
    updatedAt: waktu,
    deletedAt: batal ? waktu : null,
    syncStatus: 'synced',
  );

  TransactionItem item(String tx, String produk, int qty, int harga) =>
      TransactionItem(
        id: '$tx-$produk',
        transactionId: tx,
        productId: produk,
        productName: 'Nama $produk',
        qty: qty,
        priceAtSale: harga,
        subtotal: qty * harga,
        createdAt: hari,
        updatedAt: hari,
        syncStatus: 'synced',
      );

  Shift shift(DateTime mulai, [DateTime? selesai]) => Shift(
    id: 's${mulai.hour}',
    userId: 'budi',
    startAt: mulai,
    endAt: selesai,
    updatedAt: mulai,
    syncStatus: 'synced',
  );

  Product produk(String id, String? kategori, {bool hapus = false}) => Product(
    id: id,
    name: 'Produk $id',
    price: 10000,
    categoryId: kategori,
    hasSpicyOption: false,
    hasSweetOption: false,
    hasIceOption: false,
    createdAt: hari,
    updatedAt: hari,
    deletedAt: hapus ? hari : null,
    syncStatus: 'synced',
  );

  final kategori = [
    Category(
      id: 'k-makan',
      name: 'Makanan',
      iconCodepoint: null,
      createdAt: hari,
      updatedAt: hari,
      syncStatus: 'synced',
    ),
  ];

  RingkasanLaporan ringkas({
    Periode? periode,
    List<Transaction> transaksi = const [],
    Map<String, List<TransactionItem>> isi = const {},
    List<Shift> shiftHari = const [],
    List<Product> semuaProduk = const [],
    DateTime? sekarang,
  }) => ringkasLaporan(
    periode: periode ?? Periode.hari(hari),
    transaksi: transaksi,
    item: isi,
    pengeluaran: const [],
    shift: shiftHari,
    produk: semuaProduk,
    kategori: kategori,
    sekarang: sekarang ?? jam(23),
  );

  group('hitungan', () {
    final transaksi = [
      trx('a', jam(9), 30000),
      trx('b', jam(10), 20000, metode: 'qris', tipe: 'delivery'),
      // Dari HP yang belum diperbarui: dihitung Dine In.
      trx('c', jam(11), 10000, tipe: 'take_away'),
      trx('x', jam(12), 99000, batal: true),
    ];
    final r = ringkas(
      transaksi: transaksi,
      shiftHari: [shift(jam(8), jam(16))],
      isi: {
        'a': [item('a', 'p1', 3, 10000)],
        'b': [item('b', 'p2', 1, 20000)],
        'c': [item('c', 'p-hapus', 1, 10000)],
      },
      semuaProduk: [
        produk('p1', 'k-makan'),
        produk('p2', null),
        produk('p-sepi', 'k-makan'),
        produk('p-hapus', 'k-makan', hapus: true),
        produk('p-hapus-sepi', 'k-makan', hapus: true),
      ],
    );

    test('yang dibatalkan tidak dihitung, tapi dikumpulkan', () {
      expect(r.pendapatan, 60000);
      expect(r.jumlahTransaksi, 3);
      expect(r.rataRata, 20000);
      expect(r.transaksiBatal.map((t) => t.id), ['x']);
      expect(r.nilaiTransaksiBatal, 99000);
      expect((r.tunai.jumlah, r.tunai.nilai), (2, 40000));
      expect((r.qris.jumlah, r.qris.nilai), (1, 20000));
      expect((r.dineIn.jumlah, r.delivery.jumlah), (2, 1));
      expect((r.jumlahShift, r.jumlahHari), (1, 1));
    });

    test('per produk: yang tidak laku ikut, yang dihapus hanya kalau laku', () {
      final nama = {for (final p in r.perProduk) p.nama: p};
      expect(
        nama.keys,
        unorderedEquals([
          'Produk p1',
          'Produk p2',
          'Produk p-sepi',
          'Produk p-hapus',
        ]),
      );
      expect(nama['Produk p1']!.terjual, 3);
      expect(nama['Produk p-sepi']!.terjual, 0);
      expect(
        nama['Produk p-hapus']!.nilai,
        10000,
        reason: 'diambil dari riwayat transaksi',
      );
      expect(nama['Produk p2']!.kategori, 'Tanpa Kategori');
      expect(nama['Produk p2']!.punyaKategori, isFalse);
      expect(nama['Produk p1']!.punyaKategori, isTrue);
    });

    test('per kategori: terbesar dulu, totalnya sama dengan pendapatan', () {
      expect(
        [for (final k in r.perKategori) (k.nama, k.nilai)],
        [('Makanan', 40000), ('Tanpa Kategori', 20000)],
      );
    });
  });

  group('grafik', () {
    List<String> label(RingkasanLaporan r) => [
      for (final b in r.grafik) b.label,
    ];

    test('1 hari: rentang jam mengikuti shift hari itu', () {
      final r = ringkas(
        shiftHari: [shift(jam(8, 15), jam(16, 40))],
        transaksi: [trx('a', jam(9, 30), 15000)],
      );
      expect(r.judulGrafik, 'Pendapatan per jam');
      expect(r.grafik, hasLength(9), reason: '08 sampai 16');
      expect(label(r).take(3), ['08', '', '10']);
      expect(r.grafik[1].nilai, 15000);
    });

    test('dua shift: dari buka pertama sampai tutup terakhir', () {
      final r = ringkas(
        shiftHari: [shift(jam(8), jam(14)), shift(jam(14, 5), jam(21, 30))],
      );
      expect((r.grafik.length, label(r).first), (14, '08'));
    });

    test('shift masih berjalan: sampai jam sekarang', () {
      final r = ringkas(shiftHari: [shift(jam(13, 26))], sekarang: jam(15, 41));
      expect(r.grafik, hasLength(3), reason: '13, 14, 15');
    });

    test('transaksi di luar jam shift tetap masuk grafik', () {
      final r = ringkas(
        shiftHari: [shift(jam(8), jam(10))],
        transaksi: [trx('a', jam(12), 5000)],
      );
      expect(r.grafik, hasLength(5));
      expect(r.grafik.last.nilai, 5000);
    });

    test('tanpa shift: tanda kosong', () {
      final r = ringkas();
      expect(r.tanpaShift, isTrue);
      expect(r.grafik, isEmpty);
    });

    test('per hari: nama hari (≤7), lalu tanggal berselang', () {
      final minggu = ringkas(
        periode: Periode(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
      );
      expect(minggu.judulGrafik, 'Pendapatan per hari');
      expect(label(minggu), ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min']);

      final sepuluh = ringkas(
        periode: Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 10)),
      );
      expect(label(sepuluh).take(4), ['1', '', '3', '']);
    });

    test('lebih dari 31 hari: per bulan', () {
      final r = ringkas(
        periode: Periode(DateTime(2026, 8, 1), DateTime(2026, 10, 5)),
        transaksi: [trx('a', DateTime(2026, 9, 9, 10), 7000)],
      );
      expect(r.judulGrafik, 'Pendapatan per bulan');
      expect(label(r), ['Agu', 'Sep', 'Okt']);
      expect(r.grafik[1].nilai, 7000);
    });

    test('nama lengkap untuk gelembung', () {
      final perJam = ringkas(shiftHari: [shift(jam(8), jam(9))]);
      expect(perJam.grafik.first.nama, 'Jam 08:00');
      final perHari = ringkas(
        periode: Periode(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
      );
      expect(perHari.grafik.first.nama, 'Sen, 28 Sep');
      final perBulan = ringkas(
        periode: Periode(DateTime(2026, 8, 1), DateTime(2026, 10, 5)),
      );
      expect(perBulan.grafik.last.nama, 'Okt 2026');
    });
  });

  group('gelembung grafik', () {
    final batang = [
      for (var i = 0; i < 8; i++)
        BatangGrafik('$i', (i + 1) * 1000, nama: 'Batang $i'),
    ];

    Future<void> pasang(WidgetTester t) async {
      int? terpilih;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
              child: StatefulBuilder(
                builder: (context, setState) => GrafikBatang(
                  batang: batang,
                  terpilih: terpilih,
                  onPilih: (i) => setState(() => terpilih = i),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Finder kolom(int i) => find
        .descendant(
          of: find.byType(GrafikBatang),
          matching: find.byType(GestureDetector),
        )
        .at(i);

    testWidgets('ketuk: gelembung nama + nominal; ketuk lagi: tutup', (
      t,
    ) async {
      await pasang(t);
      expect(find.text('Batang 3'), findsNothing);

      await t.tap(kolom(3));
      await t.pumpAndSettle();
      expect(find.text('Batang 3'), findsOneWidget);
      expect(find.text('Rp 4.000'), findsOneWidget);

      await t.tap(kolom(5));
      await t.pumpAndSettle();
      expect(find.text('Batang 3'), findsNothing, reason: 'satu gelembung');
      expect(find.text('Batang 5'), findsOneWidget);

      await t.tap(kolom(5));
      await t.pumpAndSettle();
      expect(find.text('Batang 5'), findsNothing);
    });

    testWidgets('batang paling tepi: gelembung tidak keluar grafik', (t) async {
      await pasang(t);
      final grafik = t.getRect(find.byType(GrafikBatang));
      for (final i in [0, 7]) {
        await t.tap(kolom(i));
        await t.pumpAndSettle();
        final g = t.getRect(
          find
              .ancestor(
                of: find.text('Batang $i'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(g.left, greaterThanOrEqualTo(grafik.left - 0.5));
        expect(g.right, lessThanOrEqualTo(grafik.right + 0.5));
        expect(g.bottom, lessThan(grafik.bottom), reason: 'di atas batang');
      }
    });
  });

  group('halaman', () {
    late AppDatabase db;
    late LaporanRepository repo;
    final sekarang = DateTime.now();
    final pagi = DateTime(sekarang.year, sekarang.month, sekarang.day, 0, 5);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LaporanRepository(db);
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s'),
              userId: 'budi',
              startAt: Value(pagi),
            ),
          );
      for (var i = 0; i < 7; i++) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: Value('p$i'),
                name: 'Menu $i',
                price: 1000,
              ),
            );
      }
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: const Value('t1'),
              invoiceNo: const Value('TRX/1'),
              shiftId: const Value('s'),
              total: 9000,
              paymentMethod: 'cash',
              createdAt: Value(pagi),
            ),
          );
      // Menu 6 paling banyak terjual, Menu 5 paling besar pendapatannya.
      await db
          .into(db.transactionItems)
          .insert(
            TransactionItemsCompanion.insert(
              id: const Value('i1'),
              transactionId: 't1',
              productId: 'p6',
              productName: const Value('Menu 6'),
              qty: 4,
              priceAtSale: 1000,
              subtotal: 4000,
            ),
          );
      await db
          .into(db.transactionItems)
          .insert(
            TransactionItemsCompanion.insert(
              id: const Value('i2'),
              transactionId: 't1',
              productId: 'p5',
              productName: const Value('Menu 5'),
              qty: 1,
              priceAtSale: 5000,
              subtotal: 5000,
            ),
          );
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: const Value('e1'),
              userId: 'budi',
              description: 'Es batu',
              amount: 2000,
              createdAt: Value(pagi),
            ),
          );
    });
    tearDown(() => db.close());

    Future<void> buka(WidgetTester t, {required bool owner}) async {
      t.view.physicalSize = const Size(1080, 9000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      await SessionManager.instance.setSession(
        AuthSession.create(
          userId: owner ? 'o' : 'budi',
          username: owner ? 'owner' : 'budi',
          role: owner ? 'owner' : 'cashier',
          shiftId: null,
          permissions: owner ? const [] : const ['view_report'],
        ),
      );
      addTearDown(SessionManager.instance.clearSession);
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LaporanPage(repo: repo)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await t.pump();
    }

    /// Kueri pantau drift menyisakan timer nol detik saat halaman dibuang.
    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(Duration.zero);
    }

    /// Posisi teks; yang PERTAMA kalau muncul lebih dari sekali (judul kartu
    /// "Pendapatan" dan pilihan urut "Pendapatan").
    double y(WidgetTester t, String teks) =>
        t.getTopLeft(find.text(teks).first).dy;

    testWidgets('owner: semua bagian sesuai urutan desain', (t) async {
      await buka(t, owner: true);
      final urutan = [
        'Unduh Laporan',
        'Pendapatan',
        'Transaksi Dibatalkan',
        'Pengeluaran Dibatalkan',
        'Tren Pendapatan',
        'Metode Pembayaran',
        'Tipe Pesanan',
        'Pendapatan per Kategori',
        'Pendapatan per Produk',
      ];
      for (var i = 1; i < urutan.length; i++) {
        expect(
          y(t, urutan[i]),
          greaterThan(y(t, urutan[i - 1])),
          reason: '"${urutan[i]}" di bawah "${urutan[i - 1]}"',
        );
      }
      expect(find.text('Laba kotor'), findsOneWidget);
      expect(find.text('Rp 7.000'), findsOneWidget, reason: '9.000 − 2.000');
      expect(
        find.text('Tidak ada transaksi yang dibatalkan pada periode ini.'),
        findsOneWidget,
      );
      await lepas(t);
    });

    testWidgets('produk: 5 dulu, urutan Pendapatan/Terjual, lihat semua', (
      t,
    ) async {
      await buka(t, owner: true);
      expect(find.text('Lihat semua 7 produk'), findsOneWidget);
      // Produk tanpa kategori: cukup "N terjual", tanpa tulisan kategori.
      expect(find.text('4 terjual'), findsOneWidget);
      expect(find.textContaining('terjual · '), findsNothing);
      expect(
        find.text('Menu 4'),
        findsNothing,
        reason: 'baru 5 teratas; yang tidak laku urut nama',
      );
      expect(
        y(t, 'Menu 5'),
        lessThan(y(t, 'Menu 6')),
        reason: 'urut Pendapatan: Rp 5.000 di atas Rp 4.000',
      );

      await t.tap(find.text('Terjual'));
      await t.pumpAndSettle();
      expect(
        y(t, 'Menu 6'),
        lessThan(y(t, 'Menu 5')),
        reason: 'urut Terjual: 4 di atas 1',
      );

      await t.tap(find.text('Lihat semua 7 produk'));
      await t.pumpAndSettle();
      expect(find.text('Tampilkan lebih sedikit'), findsOneWidget);
      expect(find.text('Menu 4'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('ganti periode mereset gelembung grafik', (t) async {
      await buka(t, owner: true);
      await t.tap(
        find
            .descendant(
              of: find.byType(GrafikBatang),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await t.pump();
      expect(find.text('Jam 00:00'), findsOneWidget);

      await t.tap(find.byType(KartuPeriode));
      await t.pumpAndSettle();
      // Periode yang tetap punya grafik (7 batang per hari) — kalau pilihan
      // tidak direset, batang pertamanya ikut bergelembung.
      await t.ensureVisible(find.text('7 Hari Terakhir'));
      await t.pumpAndSettle();
      await t.tap(find.text('7 Hari Terakhir'));
      await t.pump();
      await t.tap(find.text('Terapkan'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      final teksGrafik = find.descendant(
        of: find.byType(GrafikBatang),
        matching: find.byType(Text),
      );
      expect(teksGrafik, findsNWidgets(7), reason: 'hanya label hari');
      await lepas(t);
    });

    testWidgets(
      'kasir tanpa izin pengeluaran: bagian pengeluaran tersembunyi',
      (t) async {
        await buka(t, owner: false);
        expect(find.text('Rata-rata / transaksi'), findsOneWidget);
        expect(find.text('Laba kotor'), findsNothing);
        expect(find.text('Pengeluaran Dibatalkan'), findsNothing);
        await lepas(t);
      },
    );
  });
}
