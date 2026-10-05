import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/ui/header_teras.dart';
import 'package:kasir_app/shared/widgets/transaction_detail_sheet.dart';

/// Lembar Detail Transaksi: selalu menyisakan area gelap di atas untuk
/// diketuk menutup; judul dan tombol tetap, hanya struk yang digulir, dengan
/// bayangan sebagai tanda masih ada isi di atas/bawah.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  /// Buka lembar berisi [jumlahMenu] baris di layar seukuran Pixel 8a
  /// (1080×2400 @2.625, status bar ±52 dp), atau setinggi [tinggiFisik].
  Future<void> buka(
    WidgetTester t,
    int jumlahMenu, {
    double tinggiFisik = 2400,
  }) async {
    t.view.physicalSize = Size(1080, tinggiFisik);
    t.view.devicePixelRatio = 2.625;
    t.view.padding = const FakeViewPadding(top: 52 * 2.625);
    addTearDown(t.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late Transaction tx;
    await t.runAsync(() async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: const Value('t1'),
              invoiceNo: const Value('TRX/1'),
              total: jumlahMenu * 10000,
              paymentMethod: 'cash',
            ),
          );
      for (var i = 0; i < jumlahMenu; i++) {
        await db
            .into(db.transactionItems)
            .insert(
              TransactionItemsCompanion.insert(
                id: Value('i$i'),
                transactionId: 't1',
                productId: 'p$i',
                productName: Value('Menu $i'),
                qty: 1,
                priceAtSale: 10000,
                subtotal: 10000,
              ),
            );
      }
      tx = await db.select(db.transactions).getSingle();
    });

    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => TransactionDetailSheet(
                    transaction: tx,
                    repo: SalesRepository(db),
                  ),
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pumpAndSettle();
  }

  /// (bayangan di bawah judul, bayangan di atas tombol).
  (bool, bool) bayangan(WidgetTester t) {
    final b = t
        .widgetList<BayanganHeader>(find.byType(BayanganHeader))
        .toList();
    expect(b, hasLength(2));
    return (
      b.firstWhere((x) => !x.keAtas).terlihat,
      b.firstWhere((x) => x.keAtas).terlihat,
    );
  }

  testWidgets('struk panjang: tinggi dibatasi, hanya struk yang digulir', (
    t,
  ) async {
    await buka(t, 30);

    final tinggiLayar = t.view.physicalSize.height / t.view.devicePixelRatio;
    final ruang = tinggiLayar - 52;
    final lembar = t.getRect(
      find
          .descendant(
            of: find.byType(TransactionDetailSheet),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(lembar.height, lessThanOrEqualTo(ruang * 0.85 + 0.5));
    expect(lembar.top, greaterThan(52 + 60), reason: 'area gelap di atas');

    // Tombol tetap di tempat: terlihat tanpa menggulir, di dalam lembar.
    final tombol = t.getRect(find.text('Cetak ulang struk'));
    expect(tombol.bottom, lessThanOrEqualTo(lembar.bottom));
    expect(
      t.getRect(find.text('Terima Kasih!')).top,
      greaterThan(tombol.top),
      reason: 'akhir struk masih di luar pandangan, belum digulir',
    );

    // Baru dibuka: tanda "masih ada di bawah" langsung tampil.
    expect(bayangan(t), (false, true));

    // Hanya struk yang digulir; judul dan tombol tidak bergeser.
    final judul = t.getRect(find.text('Detail Transaksi'));
    await t.drag(find.byType(Scrollable).last, const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Detail Transaksi')), judul);
    expect(t.getRect(find.text('Cetak ulang struk')), tombol);
    expect(bayangan(t), (true, false), reason: 'sudah mentok di akhir struk');

    // Ketuk area gelap di atas lembar → tertutup.
    await t.tapAt(Offset(200, lembar.top - 30));
    await t.pumpAndSettle();
    expect(find.byType(TransactionDetailSheet), findsNothing);
  });

  testWidgets('struk yang muat seluruhnya: tanpa bayangan', (t) async {
    // Di Pixel 8a struk satu menu pun sudah perlu digulir; layar tinggi
    // (mis. tablet) memuat semuanya.
    await buka(t, 1, tinggiFisik: 4800);
    expect(bayangan(t), (false, false));
  });
}
