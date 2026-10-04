import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/history/models/kelompok_riwayat.dart';
import 'package:kasir_app/features/history/widgets/baris_transaksi.dart';
import 'package:kasir_app/shared/ui/periode/kartu_periode.dart';
import 'package:kasir_app/shared/ui/periode/metode_filter.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:kasir_app/utils/currency_formatter.dart';

/// Riwayat owner (desain): saringan, kelompok per hari, baris batal.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Transaction trx(
    String nota,
    DateTime waktu,
    int total, {
    String metode = 'cash',
    DateTime? batal,
    String? alasan,
  }) => Transaction(
    id: 'id-$nota',
    invoiceNo: nota,
    cashierUserId: 'budi',
    createdAt: waktu,
    total: total,
    paymentMethod: metode,
    orderType: 'dine_in',
    updatedAt: waktu,
    deletedAt: batal,
    cancelReason: alasan,
    syncStatus: 'synced',
  );

  final okt = Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
  final semua = [
    trx('A1', DateTime(2026, 10, 1, 9), 10000),
    trx('A2', DateTime(2026, 10, 1, 15), 20000, metode: 'qris'),
    trx(
      'A3',
      DateTime(2026, 10, 1, 16),
      99000,
      batal: DateTime(2026, 10, 1, 17),
      alasan: 'Pelanggan batal',
    ),
    trx('B1', DateTime(2026, 10, 3, 8), 5000),
    trx('X0', DateTime(2026, 9, 30, 23, 59), 1),
    trx('X9', DateTime(2026, 10, 4, 0, 0), 1),
  ];

  group('kelompokkanRiwayat', () {
    test('per hari, terbaru dulu; total tanpa yang dibatalkan', () {
      final h = kelompokkanRiwayat(
        semua,
        periode: okt,
        metode: MetodeFilter.semua,
      );
      expect(h.map((x) => x.tanggal.day), [
        3,
        1,
      ], reason: 'di luar periode tidak ikut');
      final satu = h.last;
      expect(satu.isi.map((t) => t.invoiceNo), ['A3', 'A2', 'A1']);
      expect(satu.total, 30000, reason: 'A3 dibatalkan, tetap tampil');
    });

    test('saringan metode', () {
      final h = kelompokkanRiwayat(
        semua,
        periode: okt,
        metode: MetodeFilter.qris,
      );
      expect(h.expand((x) => x.isi).map((t) => t.invoiceNo), ['A2']);
    });

    test('cari nomor nota atau nama menu', () {
      final nota = kelompokkanRiwayat(
        semua,
        periode: okt,
        metode: MetodeFilter.semua,
        cari: 'b1',
      );
      expect(nota.expand((x) => x.isi).map((t) => t.invoiceNo), ['B1']);

      final menu = kelompokkanRiwayat(
        semua,
        periode: okt,
        metode: MetodeFilter.semua,
        cari: 'kopi',
        idCocokMenu: {'id-A1'},
      );
      expect(menu.expand((x) => x.isi).map((t) => t.invoiceNo), ['A1']);
    });
  });

  test('format nominal baris riwayat mengikuti desain', () {
    expect(formatRpRiwayat(12000), 'Rp. 12.000,00');
  });

  group('cari nama menu di database', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('budi'),
              username: 'budi',
              pinHash: 'h',
              salt: 's',
              role: 'cashier',
            ),
          );
      for (final (id, menu) in [
        ('t1', 'Kopi Susu'),
        ('t2', 'Es Teh 100%'),
        ('t3', 'Nasi Goreng'),
      ]) {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: Value(id),
                cashierUserId: const Value('budi'),
                total: 1,
                paymentMethod: 'cash',
              ),
            );
        await db
            .into(db.transactionItems)
            .insert(
              TransactionItemsCompanion.insert(
                transactionId: id,
                productId: 'p',
                productName: Value(menu),
                qty: 1,
                priceAtSale: 1,
                subtotal: 1,
              ),
            );
      }
    });
    tearDown(() => db.close());

    test('tanpa beda huruf besar/kecil', () async {
      expect(await db.idTransaksiBerisiMenu('kopi'), {'t1'});
      expect(await db.idTransaksiBerisiMenu('GORENG'), {'t3'});
    });

    test('% dicari apa adanya, bukan wildcard', () async {
      expect(await db.idTransaksiBerisiMenu('%'), {'t2'});
      expect(await db.idTransaksiBerisiMenu('   '), isEmpty);
    });
  });

  testWidgets('baris transaksi yang dibatalkan', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarisTransaksi(
            transaksi: trx(
              'OH2692184250',
              DateTime(2026, 10, 1, 9),
              12000,
              batal: DateTime(2026, 10, 1, 13, 39),
              alasan: 'Pelanggan batal',
            ),
            namaPembatal: 'owner',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Rp. 12.000,00'), findsOneWidget);
    expect(find.textContaining('Dibatalkan'), findsOneWidget);
    expect(find.textContaining('owner, 13:39'), findsOneWidget);
    expect(find.text('Alasan: Pelanggan batal'), findsOneWidget);
    expect(find.byTooltip('Batalkan'), findsNothing);
  });

  testWidgets(
    'kartu filter riwayat: nama + metode, Reset mengembalikan semua',
    (t) async {
      final hariIni = DateTime(2026, 10, 4);
      var periode = Periode.hari(hariIni);
      var metode = MetodeFilter.tunai;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, ulang) => KartuPeriode(
                periode: periode,
                metode: metode,
                hariIni: hariIni,
                onBerubah: (p) => ulang(() => periode = p),
                onBerubahMetode: (m) => ulang(() => metode = m),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hari ini · Tunai'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      await t.tap(find.text('Reset'));
      await t.pump();
      expect(metode, MetodeFilter.semua);
      expect(find.text('Hari ini'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
      await t.pumpAndSettle(const Duration(seconds: 3));
    },
  );
}
