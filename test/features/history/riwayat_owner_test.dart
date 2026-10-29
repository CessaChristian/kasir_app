import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/history/models/saringan_riwayat.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/cakupan_riwayat.dart';
import 'package:kasir_app/features/history/widgets/baris_transaksi.dart';
import 'package:kasir_app/shared/ui/periode/kartu_periode.dart';
import 'package:kasir_app/shared/ui/periode/bagian_filter.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:kasir_app/utils/currency_formatter.dart';

/// Riwayat owner (desain): saringan, kelompok per hari, baris batal.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  late SalesRepository repo;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SalesRepository(db);
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
  });
  tearDown(() => db.close());

  Future<void> trx(
    String nota,
    DateTime waktu,
    int total, {
    String metode = 'cash',
    DateTime? batal,
    String? menu,
    String? bill,
  }) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: Value('id-$nota'),
          invoiceNo: Value(nota),
          cashierUserId: const Value('budi'),
          createdAt: Value(waktu),
          total: total,
          paymentMethod: metode,
          deletedAt: Value(batal),
          billName: Value(bill),
        ));
    if (menu != null) {
      await db.into(db.transactionItems).insert(
            TransactionItemsCompanion.insert(
              transactionId: 'id-$nota',
              productId: 'p',
              productName: Value(menu),
              qty: 1,
              priceAtSale: 1,
              subtotal: 1,
            ),
          );
    }
  }

  final okt = Periode(DateTime(2026, 10, 1), DateTime(2026, 10, 3));
  Future<void> isiOktober() async {
    await trx('A1', DateTime(2026, 10, 1, 9), 10000, menu: 'Kopi Susu');
    await trx('A2', DateTime(2026, 10, 1, 15), 20000, metode: 'qris');
    await trx('A3', DateTime(2026, 10, 1, 16), 99000,
        batal: DateTime(2026, 10, 1, 17));
    await trx('B1', DateTime(2026, 10, 3, 8), 5000);
    await trx('X0', DateTime(2026, 9, 30, 23, 59), 1);
    await trx('X9', DateTime(2026, 10, 4, 0, 0), 1);
  }

  SaringanRiwayat saring({String? metode, String cari = ''}) => SaringanRiwayat(
        cakupan: CakupanRiwayat.semuaUntukTest,
        periode: okt,
        metode: metode,
        cari: cari,
      );

  Future<List<String>> nota(SaringanRiwayat s) async {
    final hari = await repo.watchHariRiwayat(s).first;
    final isi =
        await repo.watchIsiHari(s, [for (final h in hari) h.tanggal]).first;
    return [for (final t in isi) t.invoiceNo];
  }

  group('riwayat disaring di database (QA kedua K8)', () {
    test('per hari, terbaru dulu; total tanpa yang dibatalkan', () async {
      await isiOktober();
      final hari = await repo.watchHariRiwayat(saring()).first;
      expect(hari.map((h) => h.tanggal.day), [3, 1],
          reason: 'di luar periode tidak ikut');
      expect((hari.last.jumlah, hari.last.total), (3, 30000),
          reason: 'A3 dibatalkan: tetap dihitung tampil, tidak di total');
      expect(await nota(saring()), ['B1', 'A3', 'A2', 'A1']);
    });

    test('hanya hari yang diminta yang dibaca', () async {
      await isiOktober();
      final isi =
          await repo.watchIsiHari(saring(), [DateTime(2026, 10, 3)]).first;
      expect(isi.map((t) => t.invoiceNo), ['B1']);
    });

    test('saringan metode', () async {
      await isiOktober();
      expect(await nota(saring(metode: 'qris')), ['A2']);
    });

    test('cari nomor nota, nama menu, atau nama bill', () async {
      await isiOktober();
      await trx('C1', DateTime(2026, 10, 2, 10), 1000, bill: 'Meja 4 · Pak Budi');
      expect(await nota(saring(cari: 'b1')), ['B1']);
      expect(await nota(saring(cari: 'KOPI')), ['A1']);
      expect(await nota(saring(cari: 'budi')), ['C1']);
    });

    test('menu baru tertarik sinkron: hasil cari ikut berubah (QA kedua K7)',
        () async {
      await isiOktober();
      final hasil = <List<RingkasanHari>>[];
      final sub = repo.watchHariRiwayat(saring(cari: 'teh')).listen(hasil.add);
      await pumpEventQueue();
      await trx('B2', DateTime(2026, 10, 3, 9), 8000, menu: 'Es Teh');
      await pumpEventQueue();
      await sub.cancel();
      expect(hasil.first, isEmpty);
      expect(hasil.last.single.jumlah, 1);
    });

    test('nama akun baru/ganti nama ikut tampil tanpa membuka ulang '
        '(QA kedua K7)', () async {
      final nama = <Map<String, String>>[];
      final sub = db.watchNamaAkun().listen(nama.add);
      await pumpEventQueue();
      await (db.update(db.users)..where((u) => u.id.equals('budi')))
          .write(const UsersCompanion(username: Value('budi2')));
      await pumpEventQueue();
      await sub.cancel();
      expect(nama.first['budi'], 'budi');
      expect(nama.last['budi'], 'budi2');
    });

    test('% dicari apa adanya, bukan wildcard', () async {
      await isiOktober();
      await trx('D1', DateTime(2026, 10, 2, 10), 1, menu: 'Es Teh 100%');
      expect(await nota(saring(cari: '%')), ['D1']);
    });
  });

  test('format nominal baris riwayat mengikuti desain', () {
    expect(formatRpRiwayat(12000), 'Rp. 12.000,00');
  });

  testWidgets('baris transaksi yang dibatalkan', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarisTransaksi(
            transaksi: Transaction(
              id: 'id-1',
              invoiceNo: 'OH2692184250',
              cashierUserId: 'budi',
              createdAt: DateTime(2026, 10, 1, 9),
              total: 12000,
              paymentMethod: 'cash',
              orderType: 'dine_in',
              updatedAt: DateTime(2026, 10, 1, 9),
              deletedAt: DateTime(2026, 10, 1, 13, 39),
              cancelReason: 'Pelanggan batal',
              syncStatus: 'synced',
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
      String? metode = 'cash';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, ulang) => KartuPeriode(
                periode: periode,
                bagian: BagianFilter.metodeBayar,
                pilihan: metode,
                ikon: Icons.tune_rounded,
                hariIni: hariIni,
                onBerubah: (p) => ulang(() => periode = p),
                onBerubahPilihan: (m) => ulang(() => metode = m),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hari ini · Tunai'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      await t.tap(find.text('Reset'));
      await t.pump();
      expect(metode, isNull);
      expect(find.text('Hari ini'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
      await t.pumpAndSettle(const Duration(seconds: 3));
    },
  );
}
