import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/features/open_bill/sheets/lembar_open_bill.dart';
import 'package:kasir_app/features/open_bill/widgets/tombol_open_bill.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/sales/sheets/lembar_keranjang.dart';
import 'package:kasir_app/features/shift/aksi_shift.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/widgets/isi_struk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tampilan Open Bill (desain): Simpan/Perbarui Bill di keranjang, lembar
/// Tagihan Nota, hapus bill, dan "Shift belum bisa ditutup".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  late OpenBillRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = OpenBillRepository(db);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    await db
        .into(db.shifts)
        .insert(ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
    for (final (id, nama, harga) in const [
      ('latte', 'Latte', 18000),
      ('teh', 'Teh', 8000),
      ('roti', 'Roti', 12000),
    ]) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(id: Value(id), name: nama, price: harga),
          );
    }
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'k-1',
        username: 'sari',
        role: 'cashier',
        shiftId: 's-1',
        permissions: const ['create_transaction', 'open_close_shift'],
      ),
    );
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  SaleLine baris(String id, int qty) =>
      SaleLine(productId: id, productName: id, qty: qty, priceAtSale: 1);

  Future<void> tunggu(WidgetTester t, [int ms = 150]) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump();
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  Future<List<OpenBill>> semuaBill(WidgetTester t) async =>
      (await t.runAsync(() => db.select(db.openBills).get()))!;

  /// Layar dengan tombol pembuka keranjang dan daftar Open Bill.
  Future<void> pasang(WidgetTester t, Keranjang k) async {
    t.view.physicalSize = const Size(1080, 3600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [TombolOpenBill(keranjang: k, shiftId: 's-1', repo: repo)],
          ),
          body: Builder(
            builder: (c) => Column(
              children: [
                TextButton(
                  onPressed: () => bukaKeranjang(
                    c,
                    k,
                    repo: SalesRepository(db),
                    repoBill: repo,
                  ),
                  child: const Text('keranjang'),
                ),
                TextButton(
                  onPressed: () => bukaDaftarOpenBill(
                    c,
                    k,
                    repo: repo,
                    repoProduk: ProductRepository(db),
                    repoJual: SalesRepository(db),
                  ),
                  child: const Text('daftar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tunggu(t);
  }

  Future<void> bukaDaftar(WidgetTester t) async {
    await t.tap(find.text('daftar'));
    await tunggu(t);
    await t.pumpAndSettle();
  }

  testWidgets('Simpan Bill: nama wajib & tidak kembar, lalu keranjang kosong', (
    t,
  ) async {
    await t.runAsync(
      () => repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]),
    );
    final k = Keranjang()
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000)
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000);
    await pasang(t, k);
    await t.tap(find.text('keranjang'));
    await t.pumpAndSettle();
    expect(find.text('Simpan Bill'), findsOneWidget);
    await t.tap(find.text('Simpan Bill'));
    await t.pumpAndSettle();
    expect(find.text('Simpan Open Bill'), findsOneWidget);
    expect(find.text('2 item'), findsOneWidget);
    expect(find.text('Rp 36.000'), findsWidgets);

    await t.tap(find.text('Simpan'));
    await t.pump();
    expect(find.text('Nama bill wajib diisi'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'MEJA 1');
    await t.tap(find.text('Simpan'));
    await tunggu(t);
    expect(find.text('Nama sudah dipakai bill lain'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Meja 2 · Andi');
    await t.tap(find.text('Simpan'));
    await tunggu(t);
    await t.pumpAndSettle();
    expect(find.text('Bill disimpan · Meja 2 · Andi'), findsOneWidget);
    expect(find.text('Simpan Open Bill'), findsNothing);
    expect(find.text('Keranjang'), findsNothing, reason: 'keranjang ditutup');
    expect(k.isEmpty, isTrue);
    final bill = (await semuaBill(t)).firstWhere((b) => b.name != 'Meja 1');
    expect(bill.name, 'Meja 2 · Andi');
    expect(bill.shiftId, 's-1');
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('Tagihan Nota: lencana, ringkasan, muat ke keranjang, Perbarui', (
    t,
  ) async {
    await t.runAsync(() async {
      await repo.simpan(nama: 'Meja 4 · Pak Budi', baris: [baris('latte', 2)]);
      await repo.simpan(nama: 'Rina (delivery)', baris: [baris('teh', 1)]);
    });
    final k = Keranjang();
    await pasang(t, k);
    expect(find.text('2'), findsOneWidget, reason: 'lencana jumlah bill');

    await bukaDaftar(t);
    expect(find.text('Tagihan Nota'), findsOneWidget);
    expect(find.text('2 bill terbuka · Rp 44.000'), findsOneWidget);
    expect(find.text('Rp 36.000'), findsOneWidget);
    expect(find.text('2 item'), findsOneWidget);
    expect(find.textContaining(' · '), findsWidgets);

    await t.tap(find.text('Meja 4 · Pak Budi'));
    await t.pumpAndSettle();
    expect(find.text('Open bill: Meja 4 · Pak Budi'), findsOneWidget);
    expect(find.text('Perbarui Bill'), findsOneWidget);
    expect(k.bill?.nama, 'Meja 4 · Pak Budi');
    expect(k.total, 36000, reason: 'harga produk terbaru');

    // Tambah satu, lalu perbarui dengan nama yang sama.
    await t.tap(find.byTooltip('Tambah Latte'));
    await t.pump();
    await t.tap(find.text('Perbarui Bill'));
    await t.pumpAndSettle();
    expect(find.text('Perbarui Open Bill'), findsOneWidget);
    expect(find.text('3 item'), findsOneWidget);
    await t.tap(find.text('Simpan'));
    await tunggu(t);
    await t.pumpAndSettle();
    expect(find.text('Bill diperbarui · Meja 4 · Pak Budi'), findsOneWidget);
    expect((k.isEmpty, k.bill), (true, null));

    await t.pump(const Duration(seconds: 3));
    await bukaDaftar(t);
    expect(find.text('Rp 54.000'), findsOneWidget, reason: '3 × 18.000');
    expect(find.text('Di keranjang'), findsNothing);
    await lepas(t);
  });

  testWidgets('keranjang berisi pesanan lain: diminta simpan/kosongkan dulu', (
    t,
  ) async {
    await t.runAsync(
      () => repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]),
    );
    final k = Keranjang()..tambah(idProduk: 'roti', nama: 'Roti', harga: 12000);
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 1'));
    await t.pump();
    expect(
      find.text('Simpan atau kosongkan keranjang terlebih dahulu'),
      findsOneWidget,
    );
    expect(k.bill, isNull);
    expect(k.baris.single.productId, 'roti', reason: 'keranjang utuh');
    expect(find.text('Tagihan Nota'), findsOneWidget, reason: 'tetap terbuka');
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('pindah bill & produk yang sudah dihapus owner', (t) async {
    await t.runAsync(() async {
      await repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]);
      await repo.simpan(
        nama: 'Meja 2',
        baris: [baris('latte', 1), baris('roti', 2)],
      );
      await (db.update(db.products)..where((p) => p.id.equals('roti'))).write(
        ProductsCompanion(deletedAt: Value(DateTime.now())),
      );
    });
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 1'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10)); // tutup keranjang
    await t.pumpAndSettle();

    await bukaDaftar(t);
    expect(find.text('Di keranjang'), findsOneWidget);
    await t.tap(find.text('Meja 2'));
    await t.pump();
    expect(
      find.text('1 produk sudah tidak dijual dan dihapus dari bill'),
      findsOneWidget,
    );
    expect(k.bill?.nama, 'Meja 2');
    expect(k.baris.map((b) => b.productId), ['latte']);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('pindah ke bill lain: keranjang diganti', (t) async {
    await t.runAsync(() async {
      await repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]);
      await repo.simpan(nama: 'Meja 2', baris: [baris('latte', 1)]);
    });
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 1'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await bukaDaftar(t);
    await t.tap(find.text('Meja 2'));
    await t.pump();
    expect(find.text('Keranjang diganti dengan bill Meja 2'), findsOneWidget);
    expect(k.baris.single.productId, 'latte');
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('hapus bill yang sedang di keranjang', (t) async {
    await t.runAsync(
      () => repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]),
    );
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 1'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await bukaDaftar(t);
    await t.tap(find.byTooltip('Hapus bill'));
    await t.pumpAndSettle();
    expect(find.text('Hapus bill Meja 1?'), findsOneWidget);
    expect(find.textContaining('sedang ada di keranjang'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tunggu(t);
    await t.pumpAndSettle();
    expect(find.text('Bill Meja 1 dihapus'), findsOneWidget);
    expect((k.isEmpty, k.bill), (true, null));
    expect(find.text('Belum ada open bill'), findsOneWidget);
    expect((await semuaBill(t)).single.deletedAt, isNotNull);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('bayar bill dari keranjang: lunas & nama bill di transaksi', (
    t,
  ) async {
    await t.runAsync(
      () => repo.simpan(nama: 'Meja 4', baris: [baris('latte', 1)]),
    );
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 4'));
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pump();
    await t.tap(find.text('Bayar Rp 18.000'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pumpAndSettle();
    final tx = (await t.runAsync(() => db.select(db.transactions).get()))!;
    expect(tx.single.billName, 'Meja 4');
    expect((await semuaBill(t)).single.transactionId, tx.single.id);
    expect((k.isEmpty, k.bill), (true, null));
    await tunggu(t, 300);
    expect(find.text('Pelanggan'), findsOneWidget, reason: 'di struk');
    expect(find.text('Meja 4'), findsOneWidget);
    await t.tap(find.text('Selesai'));
    await t.pumpAndSettle();
    expect(find.text('2'), findsNothing);
    await lepas(t);
  });

  testWidgets('tutup shift ditolak selama masih ada open bill', (t) async {
    await t.runAsync(() async {
      await repo.simpan(nama: 'Meja 1', baris: [baris('teh', 1)]);
      await repo.simpan(nama: 'Meja 2', baris: [baris('teh', 1)]);
    });
    var dilihat = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => tutupShiftLewatDialog(
              c,
              repo: ShiftRepository(db),
              repoBill: repo,
              onLihatOpenBill: () => dilihat++,
            ),
            child: const Text('tutup'),
          ),
        ),
      ),
    );
    await t.tap(find.text('tutup'));
    await tunggu(t);
    await t.pumpAndSettle();
    expect(find.text('Shift belum bisa ditutup'), findsOneWidget);
    expect(
      find.text(
        'Masih ada 2 open bill yang belum dibayar. Selesaikan pembayaran '
        'atau hapus bill tersebut sebelum menutup shift.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tutup shift sekarang?'), findsNothing);
    await t.tap(find.text('Lihat Open Bill'));
    await t.pumpAndSettle();
    expect(dilihat, 1);
    expect(SessionManager.instance.currentSession!.shiftId, 's-1');

    await t.tap(find.text('tutup'));
    await tunggu(t);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Tutup'));
    await t.pumpAndSettle();
    expect(dilihat, 1, reason: 'Tutup hanya menutup dialog');
    expect(SessionManager.instance.currentSession!.shiftId, 's-1');
    await lepas(t);
  });

  testWidgets('struk: baris Pelanggan hanya kalau ada nama bill', (t) async {
    Transaction tx(String? bill) => Transaction(
      id: 't',
      invoiceNo: 'TRX/1',
      createdAt: DateTime(2026, 10, 14, 10),
      total: 1000,
      paymentMethod: 'qris',
      orderType: 'dine_in',
      billName: bill,
      updatedAt: DateTime(2026, 10, 14, 10),
      syncStatus: 'synced',
    );
    Future<void> struk(String? bill) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IsiStruk(
              transaksi: tx(bill),
              items: const [],
              namaKasir: 'sari',
            ),
          ),
        ),
      ),
    );
    await struk('Meja 4 · Pak Budi');
    expect(find.text('Pelanggan'), findsOneWidget);
    expect(find.text('Meja 4 · Pak Budi'), findsOneWidget);
    await struk(null);
    expect(find.text('Pelanggan'), findsNothing);
  });
}
