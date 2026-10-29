import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/open_bill/models/isi_bill.dart';
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

  group('QA S5: pindah bill padahal bill di keranjang sudah diubah', () {
    Future<Keranjang> mejaSatuDitambah(WidgetTester t) async {
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
      k.tambahSatu(0); // 2 Teh, belum "Perbarui Bill"
      await bukaDaftar(t);
      await t.tap(find.text('Meja 2'));
      await t.pumpAndSettle();
      return k;
    }

    Future<String> isiMejaSatu(WidgetTester t) async => (await semuaBill(t))
        .firstWhere((b) => b.name == 'Meja 1')
        .items;

    testWidgets('ditanya dulu, tidak diganti diam-diam', (t) async {
      final k = await mejaSatuDitambah(t);
      expect(find.text('Bill Meja 1 ada perubahan yang belum disimpan'),
          findsOneWidget);
      expect(k.bill?.nama, 'Meja 1');
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(k.bill?.nama, 'Meja 1');
      expect(k.baris.single.qty, 2);
      await lepas(t);
    });

    testWidgets('Simpan ke Meja 1: tambahan tersimpan, lalu Meja 2 dibuka', (
      t,
    ) async {
      final k = await mejaSatuDitambah(t);
      await t.tap(find.text('Simpan ke Meja 1'));
      await tunggu(t);
      await t.pumpAndSettle();
      expect(isiBillSama(await isiMejaSatu(t), kodekanIsiBill([baris('teh', 2)])),
          isTrue);
      expect(k.bill?.nama, 'Meja 2');
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    testWidgets('Buang perubahan: Meja 1 tetap, Meja 2 dibuka', (t) async {
      final k = await mejaSatuDitambah(t);
      await t.tap(find.text('Buang perubahan'));
      await tunggu(t);
      await t.pumpAndSettle();
      expect(isiBillSama(await isiMejaSatu(t), kodekanIsiBill([baris('teh', 1)])),
          isTrue);
      expect(k.bill?.nama, 'Meja 2');
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });
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

  /// Muat bill "Meja 4" ke keranjang lewat Tagihan Nota, lalu buka ulang
  /// keranjangnya dengan [server] sebagai repositori bill, dan bayar QRIS.
  Future<Keranjang> bayarBill(WidgetTester t, _ServerTiruan server) async {
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 4'));
    await t.pumpAndSettle();
    Navigator.of(t.element(find.text('Keranjang'))).pop();
    await t.pumpAndSettle();
    final c = t.element(find.text('keranjang'));
    // ignore: unawaited_futures
    bukaKeranjang(c, k, repo: SalesRepository(db), repoBill: server);
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pump();
    await t.tap(find.text('Bayar Rp 18.000'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    return k;
  }

  /// Ditolak karena bill: keranjang kosong & lepas dari bill, lembar
  /// pembayaran dan keranjang tertutup, toast menjelaskan.
  void cekDitolak(Keranjang k, String apa) {
    expect((k.isEmpty, k.bill), (true, null), reason: 'keranjang dikosongkan');
    expect(find.text('Sudah Bayar'), findsNothing, reason: 'lembar bayar');
    expect(find.text('Keranjang'), findsNothing, reason: 'lembar keranjang');
    expect(
      find.text(
        'Bill Meja 4 sudah $apa di perangkat lain. Keranjang dikosongkan.',
      ),
      findsOneWidget,
    );
  }

  Future<String> simpanMeja4(WidgetTester t) async => (await t.runAsync(
    () => repo.simpan(nama: 'Meja 4', baris: [baris('latte', 1)]),
  ))!;

  Future<List<Transaction>> semuaTx(WidgetTester t) async =>
      (await t.runAsync(() => db.select(db.transactions).get()))!;

  for (final (keputusan, kata) in const [
    (KeputusanServer.sudahDibayar, 'dibayar'),
    (KeputusanServer.sudahDihapus, 'dihapus'),
  ]) {
    testWidgets('bayar bill yang sudah $kata HP lain: klaim kalah, ditolak', (
      t,
    ) async {
      final id = await simpanMeja4(t);
      // Tarikan data server sengaja tidak pernah selesai: bill harus sudah
      // tertutup di HP ini tanpa menunggunya.
      final server = _ServerTiruan(db, klaim: keputusan);
      final k = await bayarBill(t, server);

      expect(server.catatan, ['cek', 'klaim', 'segarkan']);
      cekDitolak(k, kata);
      final bill = (await semuaBill(t)).singleWhere((b) => b.id == id);
      expect(bill.deletedAt, isNotNull, reason: 'langsung tertutup di HP');
      expect(await semuaTx(t), isEmpty, reason: 'tidak ada transaksi kedua');
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });
  }

  testWidgets('bayar bill, server tak terjawab: tetap tersimpan', (t) async {
    await simpanMeja4(t);
    final server = _ServerTiruan(db, klaim: KeputusanServer.takTerjawab);
    await bayarBill(t, server);
    await t.pumpAndSettle();
    expect(server.catatan, ['cek', 'klaim']);
    expect((await semuaTx(t)).single.billName, 'Meja 4');
    await lepas(t);
  });

  testWidgets('HP ini sudah tahu bill tak terbuka: klaim dilepas, ditolak', (
    t,
  ) async {
    final id = await simpanMeja4(t);
    // Server tak terjawab (offline), tapi HP ini sudah menarik kabar bill
    // itu terhapus — createSale menolak.
    final server = _ServerTiruan(db, klaim: KeputusanServer.takTerjawab)
      ..sebelumKlaim = () =>
          (db.update(db.openBills)..where((b) => b.id.equals(id))).write(
            OpenBillsCompanion(deletedAt: Value(DateTime.now())),
          );
    final k = await bayarBill(t, server);
    expect(server.catatan, ['cek', 'klaim', 'lepas']);
    cekDitolak(k, 'dibayar atau dihapus');
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('galat lain: lembar tetap terbuka, keranjang utuh', (t) async {
    await simpanMeja4(t);
    // Produknya dihapus owner tepat sebelum disimpan — bukan soal bill.
    final server = _ServerTiruan(db)
      ..sebelumKlaim = () =>
          (db.update(db.products)..where((p) => p.id.equals('latte'))).write(
            ProductsCompanion(deletedAt: Value(DateTime.now())),
          );
    final k = await bayarBill(t, server);
    expect(server.catatan, ['cek', 'klaim', 'lepas']);
    expect(k.isEmpty, isFalse);
    expect(k.bill?.nama, 'Meja 4');
    expect(find.text('Sudah Bayar'), findsOneWidget);
    // Pesannya sendiri, tanpa "Gagal: Bad state:" di depannya.
    expect(
      find.text(
        '"Latte" sudah tidak tersedia. '
        'Hapus produk ini dari keranjang sebelum melanjutkan.',
      ),
      findsOneWidget,
    );
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('bayar tanpa bill: server tidak ditanya', (t) async {
    final server = _ServerTiruan(db);
    final k = Keranjang()
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000);
    await pasang(t, k);
    final c = t.element(find.text('keranjang'));
    // ignore: unawaited_futures
    bukaKeranjang(c, k, repo: SalesRepository(db), repoBill: server);
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pump();
    await t.tap(find.textContaining('Bayar Rp'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pumpAndSettle();
    expect(server.catatan, isEmpty);
    expect(await semuaTx(t), hasLength(1));
    await lepas(t);
  });

  testWidgets('bayar bill yang sudah ditambah HP lain: keranjang diperbarui, '
      'tidak ada pesanan yang lolos tertagih', (t) async {
    final id = await simpanMeja4(t);
    // HP lain menambah Teh ke Meja 4 sesudah HP ini memuatnya (Latte×1).
    final isiBaru = kodekanBarisBill([
      (idProduk: 'latte', jumlah: 1, catatan: null),
      (idProduk: 'teh', jumlah: 1, catatan: null),
    ]);
    final server = _ServerTiruan(db)..isiServer = isiBaru;
    final k = await bayarBill(t, server);
    await t.pumpAndSettle();

    expect(server.catatan, ['cek'], reason: 'belum diklaim');
    expect(await semuaTx(t), isEmpty, reason: 'Rp18.000 tidak boleh tercatat');
    expect(
      find.text(
        'Bill Meja 4 sudah diubah di perangkat lain. '
        'Keranjang diperbarui — periksa totalnya lalu bayar lagi.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sudah Bayar'), findsNothing, reason: 'lembar bayar');
    expect(find.text('Keranjang'), findsOneWidget, reason: 'tetap terbuka');
    expect(k.baris.map((b) => (b.productId, b.qty)), [('latte', 1), ('teh', 1)]);
    expect(k.bill, (id: id, nama: 'Meja 4', isiAwal: isiBaru));

    // Dibayar lagi dengan isi yang sudah sama dengan server: lunas penuh.
    await t.tap(find.text('Bayar Rp 26.000'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pumpAndSettle();
    expect(server.catatan, ['cek', 'cek', 'klaim']);
    final tx = await semuaTx(t);
    expect((tx.single.total, tx.single.billName), (26000, 'Meja 4'));
    await t.tap(find.text('Selesai'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('tambahan kasir di HP ini ikut digabung dengan tambahan HP lain', (
    t,
  ) async {
    await simpanMeja4(t);
    final server = _ServerTiruan(db)
      ..isiServer = kodekanBarisBill([
        (idProduk: 'latte', jumlah: 1, catatan: null),
        (idProduk: 'teh', jumlah: 1, catatan: null),
      ]);
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 4'));
    await t.pumpAndSettle();
    k.tambah(idProduk: 'roti', nama: 'Roti', harga: 12000);
    Navigator.of(t.element(find.text('Keranjang'))).pop();
    await t.pumpAndSettle();
    // ignore: unawaited_futures
    bukaKeranjang(
      t.element(find.text('keranjang')),
      k,
      repo: SalesRepository(db),
      repoBill: server,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pump();
    await t.tap(find.text('Bayar Rp 30.000'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pumpAndSettle();

    expect(k.baris.map((b) => (b.productId, b.qty)), [
      ('latte', 1),
      ('teh', 1),
      ('roti', 1),
    ]);
    expect(find.text('Bayar Rp 38.000'), findsOneWidget);
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('pengecekan isi bilang bill sudah dibayar: ditolak tanpa klaim', (
    t,
  ) async {
    await simpanMeja4(t);
    final server = _ServerTiruan(db, cek: KeputusanServer.sudahDibayar);
    final k = await bayarBill(t, server);
    expect(server.catatan, ['cek', 'segarkan']);
    cekDitolak(k, 'dibayar');
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  /// Buka keranjang [k] dengan repositori [jual] & [server], lalu bayar QRIS.
  Future<void> bayarDengan(
    WidgetTester t,
    Keranjang k,
    SalesRepository jual,
    _ServerTiruan server,
    String tombol,
  ) async {
    // ignore: unawaited_futures
    bukaKeranjang(
      t.element(find.text('keranjang')),
      k,
      repo: jual,
      repoBill: server,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pump();
    await t.tap(find.text(tombol));
    await t.pumpAndSettle();
    await t.tap(find.text('Sudah Bayar'));
    await tunggu(t, 300);
    await t.pumpAndSettle();
  }

  void cekShiftDitolak(Keranjang k) {
    expect(
      find.text(
        'Shift ini sudah ditutup di perangkat lain. Pesanan tetap di '
        'keranjang — buka shift baru lalu bayar lagi.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sudah Bayar'), findsNothing, reason: 'lembar bayar');
    expect(find.text('Keranjang'), findsOneWidget, reason: 'tetap terbuka');
    expect(k.isEmpty, isFalse, reason: 'pesanan tidak hilang');
    expect(SessionManager.instance.currentSession?.shiftId, isNull,
        reason: 'sesi dilepas dari shift yang sudah ditutup');
  }

  testWidgets('shift sudah ditutup HP lain (kata server): tidak tersimpan, '
      'pesanan tetap di keranjang', (t) async {
    final server = _ServerTiruan(db);
    final jual = _PenjualanTiruan(db, ditutup: true);
    final k = Keranjang()
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000);
    await pasang(t, k);
    await bayarDengan(t, k, jual, server, 'Bayar Rp 18.000');
    expect(jual.ditanya, 1);
    cekShiftDitolak(k);
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('shift sudah ditutup: bill tidak diklaim', (t) async {
    await simpanMeja4(t);
    final server = _ServerTiruan(db);
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 4'));
    await t.pumpAndSettle();
    Navigator.of(t.element(find.text('Keranjang'))).pop();
    await t.pumpAndSettle();
    await bayarDengan(
        t, k, _PenjualanTiruan(db, ditutup: true), server, 'Bayar Rp 18.000');
    expect(server.catatan, isEmpty, reason: 'bill tidak dikunci');
    cekShiftDitolak(k);
    expect(k.bill?.nama, 'Meja 4');
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('shift ditutup tepat sesudah diperiksa: database menolak, '
      'ditangani sama', (t) async {
    final server = _ServerTiruan(db);
    // Server bilang masih berjalan, tapi saat disimpan HP ini sudah tahu
    // shift-nya tertutup.
    final jual = _PenjualanTiruan(db, ditutup: false)
      ..sesudahDitanya = () =>
          (db.update(db.shifts)..where((s) => s.id.equals('s-1')))
              .write(ShiftsCompanion(endAt: Value(DateTime.now())));
    final k = Keranjang()
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000);
    await pasang(t, k);
    await bayarDengan(t, k, jual, server, 'Bayar Rp 18.000');
    cekShiftDitolak(k);
    expect(await semuaTx(t), isEmpty);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  Future<void> hapusLewatDaftar(
    WidgetTester t,
    _ServerTiruan server, {
    Keranjang? keranjang,
  }) async {
    final k = keranjang ?? Keranjang();
    await pasang(t, k);
    final c = t.element(find.text('daftar'));
    // ignore: unawaited_futures
    bukaDaftarOpenBill(
      c,
      k,
      repo: server,
      repoProduk: ProductRepository(db),
      repoJual: SalesRepository(db),
    );
    await tunggu(t);
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byTooltip('Hapus bill'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hapus'));
    await tunggu(t, 300);
    await t.pump();
  }

  testWidgets('hapus bill yang sudah dibayar HP lain: ditolak', (t) async {
    final id = await simpanMeja4(t);
    final server = _ServerTiruan(
      db,
      jawabanHapus: KeputusanServer.sudahDibayar,
    );
    final sebelum = (await semuaBill(t)).single;
    await hapusLewatDaftar(t, server);
    expect(server.catatan, ['hapus', 'segarkan']);
    // Saat toast terlihat, kartunya SUDAH hilang — walau tarikan data
    // server belum selesai.
    expect(
      find.text('Bill Meja 4 sudah dibayar di perangkat lain'),
      findsOneWidget,
    );
    expect(find.text('Meja 4'), findsNothing, reason: 'kartu bill');
    expect(find.text('0 bill terbuka · Rp 0'), findsOneWidget);
    final bill = (await semuaBill(t)).singleWhere((b) => b.id == id);
    expect(bill.deletedAt, isNotNull, reason: 'ditandai tertutup di HP');
    expect(
      (bill.updatedAt, bill.syncStatus),
      (sebelum.updatedAt, sebelum.syncStatus),
      reason: 'tanda sementara: tidak ikut terkirim, kalah dari data server',
    );
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('hapus ditolak untuk bill di keranjang: keranjang kosong', (
    t,
  ) async {
    final id = await simpanMeja4(t);
    final k = Keranjang()
      ..muatBill((id: id, nama: 'Meja 4', isiAwal: '[]'), [baris('latte', 1)]);
    final server = _ServerTiruan(
      db,
      jawabanHapus: KeputusanServer.sudahDibayar,
    );
    await hapusLewatDaftar(t, server, keranjang: k);
    expect((k.isEmpty, k.bill), (true, null));
    expect(
      find.text(
        'Bill Meja 4 sudah dibayar di perangkat lain. Keranjang dikosongkan.',
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('hapus bill, server tak terjawab: dihapus di HP', (t) async {
    await simpanMeja4(t);
    final server = _ServerTiruan(db, jawabanHapus: KeputusanServer.takTerjawab);
    await hapusLewatDaftar(t, server);
    expect(server.catatan, ['hapus']);
    expect(find.text('Bill Meja 4 dihapus'), findsOneWidget);
    expect((await semuaBill(t)).single.deletedAt, isNotNull);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  /// Muat bill "Meja 4" ke keranjang, buka ulang keranjangnya dengan
  /// [server], tambah satu Latte, lalu Perbarui Bill.
  Future<Keranjang> perbaruiBill(WidgetTester t, _ServerTiruan server) async {
    final k = Keranjang();
    await pasang(t, k);
    await bukaDaftar(t);
    await t.tap(find.text('Meja 4'));
    await t.pumpAndSettle();
    Navigator.of(t.element(find.text('Keranjang'))).pop();
    await t.pumpAndSettle();
    final c = t.element(find.text('keranjang'));
    // ignore: unawaited_futures
    bukaKeranjang(c, k, repo: SalesRepository(db), repoBill: server);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Tambah Latte'));
    await t.pump();
    await t.tap(find.text('Perbarui Bill'));
    await t.pumpAndSettle();
    await t.tap(find.text('Simpan'));
    await tunggu(t, 300);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    return k;
  }

  /// Isi bill di DB: jumlah Latte-nya (1 = tidak ikut diperbarui).
  Future<int> qtyLatte(WidgetTester t, String id) async {
    final bill = (await semuaBill(t)).singleWhere((b) => b.id == id);
    return bacaIsiBill(bill.items).single.jumlah;
  }

  for (final (keputusan, kata) in const [
    (KeputusanServer.sudahDibayar, 'dibayar'),
    (KeputusanServer.sudahDihapus, 'dihapus'),
  ]) {
    testWidgets('perbarui bill yang sudah $kata HP lain: ditolak', (t) async {
      final id = await simpanMeja4(t);
      final awal = (await semuaBill(t)).single.updatedAt;
      final server = _ServerTiruan(db, cek: keputusan);
      final k = await perbaruiBill(t, server);

      expect(server.catatan, ['cek', 'segarkan']);
      cekDitolak(k, kata);
      expect(find.text('Perbarui Open Bill'), findsNothing, reason: 'dialog');
      expect(await qtyLatte(t, id), 1, reason: 'isi bill tidak diubah');
      final bill = (await semuaBill(t)).singleWhere((b) => b.id == id);
      expect(bill.deletedAt, isNotNull, reason: 'langsung tertutup di HP');
      expect(bill.updatedAt, awal, reason: 'tanda tidak ikut terkirim');
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });
  }

  testWidgets('perbarui bill, server tak terjawab: tetap tersimpan', (t) async {
    final id = await simpanMeja4(t);
    final server = _ServerTiruan(db, cek: KeputusanServer.takTerjawab);
    final k = await perbaruiBill(t, server);
    await t.pumpAndSettle();
    expect(server.catatan, ['cek']);
    expect(find.text('Bill diperbarui · Meja 4'), findsOneWidget);
    expect(k.isEmpty, isTrue);
    expect(await qtyLatte(t, id), 2);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('perbarui bill yang sudah ditambah HP lain: digabung', (t) async {
    final id = await simpanMeja4(t);
    // HP lain sudah menambah Teh; HP ini menambah Latte (perbaruiBill).
    final server = _ServerTiruan(db)
      ..isiServer = kodekanBarisBill([
        (idProduk: 'latte', jumlah: 1, catatan: null),
        (idProduk: 'teh', jumlah: 1, catatan: null),
      ]);
    final k = await perbaruiBill(t, server);
    await t.pumpAndSettle();
    expect(server.catatan, ['cek']);
    expect(
      find.text(
        'Bill diperbarui · Meja 4 (digabung dengan perubahan perangkat lain)',
      ),
      findsOneWidget,
    );
    expect(k.isEmpty, isTrue);
    final bill = (await semuaBill(t)).singleWhere((b) => b.id == id);
    expect(bacaIsiBill(bill.items).map((b) => (b.idProduk, b.jumlah)), [
      ('latte', 2),
      ('teh', 1),
    ]);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('perbarui, isi server tidak diubah HP lain: pesan biasa', (
    t,
  ) async {
    final id = await simpanMeja4(t);
    final awal = (await semuaBill(t)).single.items;
    final server = _ServerTiruan(db)..isiServer = awal;
    await perbaruiBill(t, server);
    await t.pumpAndSettle();
    expect(find.text('Bill diperbarui · Meja 4'), findsOneWidget);
    expect(await qtyLatte(t, id), 2);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('perbarui bill yang HP ini sudah tahu tak terbuka: ditolak', (
    t,
  ) async {
    final id = await simpanMeja4(t);
    // Server tak terjawab (offline), tapi HP ini sudah menarik kabar bill
    // itu terhapus — simpan menolak.
    final server = _ServerTiruan(db, cek: KeputusanServer.takTerjawab)
      ..sebelumCek = () =>
          (db.update(db.openBills)..where((b) => b.id.equals(id))).write(
            OpenBillsCompanion(deletedAt: Value(DateTime.now())),
          );
    final k = await perbaruiBill(t, server);
    expect(server.catatan, ['cek']);
    cekDitolak(k, 'dibayar atau dihapus');
    expect(await qtyLatte(t, id), 1);
    await t.pump(const Duration(seconds: 3));
    await lepas(t);
  });

  testWidgets('simpan bill baru: server tidak ditanya', (t) async {
    final server = _ServerTiruan(db);
    final k = Keranjang()
      ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000);
    await pasang(t, k);
    final c = t.element(find.text('keranjang'));
    // ignore: unawaited_futures
    bukaKeranjang(c, k, repo: SalesRepository(db), repoBill: server);
    await t.pumpAndSettle();
    await t.tap(find.text('Simpan Bill'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Meja 9');
    await t.tap(find.text('Simpan'));
    await tunggu(t);
    await t.pumpAndSettle();
    expect(server.catatan, isEmpty);
    expect(find.text('Bill disimpan · Meja 9'), findsOneWidget);
    expect((await semuaBill(t)).single.name, 'Meja 9');
    await t.pump(const Duration(seconds: 3));
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

/// Repositori bill dengan server tiruan: jawaban klaim/hapus diatur test,
/// dan setiap panggilan ke "server" dicatat urut di [catatan].
class _ServerTiruan extends OpenBillRepository {
  final KeputusanServer klaim;
  final KeputusanServer jawabanHapus;
  final KeputusanServer cek;
  final catatan = <String>[];

  /// Dijalankan sebelum klaim / cek dijawab.
  Future<void> Function()? sebelumKlaim;
  Future<void> Function()? sebelumCek;

  /// Tarikan data server yang lambat: tidak pernah selesai di test.
  final _tarikan = Completer<void>();

  _ServerTiruan(
    super.db, {
    this.klaim = KeputusanServer.boleh,
    this.jawabanHapus = KeputusanServer.boleh,
    this.cek = KeputusanServer.boleh,
  });

  /// Isi bill di server yang dijawab [cekDiServer]; null = tak terbaca.
  String? isiServer;

  @override
  Future<CekBill> cekDiServer(String billId) async {
    catatan.add('cek');
    await sebelumCek?.call();
    return (keputusan: cek, isi: isiServer);
  }

  @override
  Future<KeputusanServer> klaimDiServer(String billId, String tx) async {
    catatan.add('klaim');
    await sebelumKlaim?.call();
    return klaim;
  }

  @override
  Future<void> lepasKlaim(String billId, String tx) async =>
      catatan.add('lepas');

  @override
  Future<KeputusanServer> hapusDiServer(String billId) async {
    catatan.add('hapus');
    return jawabanHapus;
  }

  @override
  Future<void> segarkanDariServer() async {
    catatan.add('segarkan');
    await _tarikan.future;
  }
}

/// Penjualan dengan jawaban "shift sudah ditutup?" yang diatur test.
class _PenjualanTiruan extends SalesRepository {
  final bool ditutup;
  var ditanya = 0;
  Future<void> Function()? sesudahDitanya;

  _PenjualanTiruan(super.db, {required this.ditutup});

  @override
  Future<bool> shiftSudahDitutup(String shiftId) async {
    ditanya++;
    await sesudahDitanya?.call();
    return ditutup;
  }
}
