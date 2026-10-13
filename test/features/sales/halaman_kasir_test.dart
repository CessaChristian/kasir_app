import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/sales/models/pesanan.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/sales/sales_page.dart';
import 'package:kasir_app/features/sales/sheets/lembar_keranjang.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Halaman Kasir (desain): kategori 4 kolom, kisi produk, varian, keranjang,
/// pembayaran tunai/QRIS, dan struk sesudah bayar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('aturan pembayaran', () {
    test('nominal cepat: uang pas lalu pecahan bulat berikutnya', () {
      expect(nominalCepat(37000), [37000, 40000, 50000, 100000]);
      expect(nominalCepat(100000), [100000], reason: 'tanpa kembar');
      expect(nominalCepat(12000), [12000, 20000, 50000, 100000]);
    });

    test('status uang', () {
      expect(statusUang(25000, null), StatusUang.kosong);
      expect(statusUang(25000, 20000), StatusUang.kurang);
      expect(statusUang(25000, 25000), StatusUang.pas);
      expect(statusUang(25000, 30000), StatusUang.kembalian);
    });

    test('label sinkron terakhir', () {
      final kini = DateTime(2026, 10, 13, 15);
      expect(labelSinkronTerakhir(null, kini), 'Belum pernah sinkron');
      expect(
        labelSinkronTerakhir(DateTime(2026, 10, 13, 14, 32), kini),
        'Sinkron terakhir 14:32',
      );
      expect(
        labelSinkronTerakhir(DateTime(2026, 10, 12, 9, 5), kini),
        'Sinkron terakhir 12 Okt 09:05',
      );
    });
  });

  group('halaman', () {
    late AppDatabase db;

    Future<void> produk(
      String id,
      String nama,
      int harga, {
      String? kategori,
      bool pedas = false,
    }) => db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            name: nama,
            price: harga,
            categoryId: Value(kategori),
            hasSpicyOption: Value(pedas),
          ),
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
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
          .insert(
            ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'),
          );
      for (final (id, nama, tampil) in const [
        ('kopi', 'Kopi', true),
        ('snack', 'Snack', true),
        ('musim', 'Musiman', false),
      ]) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: Value(id),
                name: nama,
                tampilDiKasir: Value(tampil),
              ),
            );
      }
      await produk('latte', 'Latte', 18000, kategori: 'kopi');
      await produk('mie', 'Mie Pedas', 15000, kategori: 'snack', pedas: true);
      await produk('es', 'Es Buah', 12000, kategori: 'musim');
      await produk('air', 'Air Mineral', 5000);
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

    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 3600);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> tunggu(WidgetTester t, [int ms = 120]) async {
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pump();
    }

    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    Future<Keranjang> bukaKasir(WidgetTester t) async {
      layarHp(t);
      final k = Keranjang();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesPage(keranjang: k, repo: ProductRepository(db)),
          ),
        ),
      );
      await tunggu(t);
      return k;
    }

    testWidgets('kategori: tersembunyi tidak tampil, filter & Hapus filter', (
      t,
    ) async {
      await bukaKasir(t);
      expect(find.text('Cari Berdasarkan Kategori'), findsOneWidget);
      expect(find.text('Kopi'), findsOneWidget);
      expect(find.text('Musiman'), findsNothing);
      expect(find.text('Tanpa Kategori'), findsOneWidget);
      expect(
        find.text('Es Buah'),
        findsOneWidget,
        reason: 'produk kategori tersembunyi tetap dijual',
      );

      await t.tap(find.text('Kopi'));
      await t.pump();
      expect(find.text('Kopi · 1 produk'), findsOneWidget);
      expect(find.text('Latte'), findsOneWidget);
      expect(find.text('Air Mineral'), findsNothing);

      await t.tap(find.text('Hapus filter'));
      await t.pump();
      expect(find.text('Air Mineral'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'mie');
      await t.pump();
      expect(find.text('Mie Pedas'), findsOneWidget);
      expect(find.text('Latte'), findsNothing);
      await lepas(t);
    });

    testWidgets('ketuk produk: masuk keranjang, angka di foto', (t) async {
      final k = await bukaKasir(t);
      await t.tap(find.text('Latte'));
      await t.pump();
      await t.tap(find.text('Latte'));
      await t.pump();
      expect(k.baris.single.qty, 2);
      expect(find.text('2'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('varian: pilih → catatan; Lewati → tanpa catatan', (t) async {
      final k = await bukaKasir(t);
      await t.tap(find.text('Mie Pedas'));
      await t.pumpAndSettle();
      expect(find.text('Pilih varian pesanan:'), findsOneWidget);
      await t.tap(find.text('Sedang'));
      await t.tap(find.text('Tambah ke Keranjang'));
      await t.pumpAndSettle();
      expect(k.baris.single.notes, 'Pedas: Sedang');

      await t.tap(find.text('Mie Pedas'));
      await t.pumpAndSettle();
      await t.tap(find.text('Lewati, tambah tanpa varian'));
      await t.pumpAndSettle();
      expect(k.baris, hasLength(2));
      expect(k.baris.last.notes, isNull);
      await lepas(t);
    });

    Future<Keranjang> bukaLembar(WidgetTester t) async {
      layarHp(t);
      final k = Keranjang()
        ..tambah(idProduk: 'latte', nama: 'Latte', harga: 18000)
        ..tambah(idProduk: 'air', nama: 'Air Mineral', harga: 5000);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => bukaKeranjang(c, k, repo: SalesRepository(db)),
              child: const Text('buka'),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      return k;
    }

    testWidgets('bayar tunai: kurang → tidak bisa, kembalian, struk', (
      t,
    ) async {
      final k = await bukaLembar(t);
      expect(find.text('Total Belanja'), findsOneWidget);
      expect(find.text('Bayar Rp 23.000'), findsOneWidget);
      await t.tap(find.text('Bayar Rp 23.000'));
      await t.pumpAndSettle();
      expect(find.text('Pembayaran Tunai'), findsOneWidget);
      expect(find.text('Masukkan jumlah uang diterima'), findsOneWidget);
      for (final n in ['Rp 30.000', 'Rp 50.000', 'Rp 100.000']) {
        expect(find.text(n), findsOneWidget, reason: 'nominal cepat');
      }

      await t.enterText(find.byType(TextField), '20000');
      await t.pump();
      expect(find.text('Uang kurang'), findsOneWidget);
      expect(find.text('Rp 3.000'), findsOneWidget);
      FilledButton tombolBayar() =>
          t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Konfirmasi pembayaran'));
      expect(tombolBayar().onPressed, isNull,
          reason: 'uang kurang: tombol Bayar nonaktif');
      await t.tap(find.text('Konfirmasi pembayaran'));
      await t.pump();
      expect(await t.runAsync(() => db.select(db.transactions).get()), isEmpty);

      await t.tap(find.text('Rp 50.000'));
      await t.pump();
      expect(find.text('Kembalian'), findsOneWidget);
      expect(find.text('Rp 27.000'), findsOneWidget);
      expect(tombolBayar().onPressed, isNotNull);

      await t.tap(find.text('Konfirmasi pembayaran'));
      await tunggu(t, 300);
      await t.pumpAndSettle();
      final tx = (await t.runAsync(() => db.select(db.transactions).get()))!;
      expect(
        (tx.single.paymentMethod, tx.single.cashReceived, tx.single.change),
        ('cash', 50000, 27000),
      );
      expect(k.isEmpty, isTrue);
      await tunggu(t, 300);
      expect(find.text('Terima Kasih!'), findsOneWidget);
      expect(find.text('Cetak Struk'), findsOneWidget);
      await t.tap(find.text('Selesai'));
      await t.pumpAndSettle();
      expect(find.text('Terima Kasih!'), findsNothing);
      await lepas(t);
    });

    testWidgets('bayar QRIS + Delivery: tersimpan sesuai pilihan', (t) async {
      await bukaLembar(t);
      await t.tap(find.text('Delivery'));
      await t.tap(find.text('QRIS'));
      await t.pump();
      await t.tap(find.text('Bayar Rp 23.000'));
      await t.pumpAndSettle();
      expect(find.text('Nominal pembayaran'), findsOneWidget);
      await t.tap(find.text('Sudah Bayar'));
      await tunggu(t, 300);
      await t.pumpAndSettle();
      final tx = (await t.runAsync(() => db.select(db.transactions).get()))!;
      expect(
        (tx.single.paymentMethod, tx.single.orderType, tx.single.total),
        ('qris', 'delivery', 23000),
      );
      await tunggu(t, 300);
      expect(find.text('Selamat Menikmati'), findsOneWidget);
      await t.tap(find.text('Selesai'));
      await t.pumpAndSettle();
      await lepas(t);
    });

    testWidgets('jumlah, hapus baris, dan kosongkan (ditanya dulu)', (t) async {
      final k = await bukaLembar(t);
      await t.tap(find.byTooltip('Tambah Latte'));
      await t.pump();
      expect(k.baris.first.qty, 2);
      await t.tap(find.byTooltip('Hapus Air Mineral'));
      await t.pump();
      expect(k.jumlahBaris, 1);

      await t.tap(find.text('Kosongkan'));
      await t.pumpAndSettle();
      expect(find.text('Kosongkan keranjang?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Kosongkan'));
      await t.pumpAndSettle();
      expect(k.isEmpty, isTrue);
      expect(find.text('Keranjang Kosong'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('tanpa shift: bayar ditolak, keranjang utuh', (t) async {
      await SessionManager.instance.aturShift(null);
      final k = await bukaLembar(t);
      await t.tap(find.text('Bayar Rp 23.000'));
      await t.pump();
      expect(find.text('Pembayaran Tunai'), findsNothing);
      expect(k.jumlahBaris, 2);
      await lepas(t);
    });
  });
}
