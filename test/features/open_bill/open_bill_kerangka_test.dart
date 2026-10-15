import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/app/kerangka_kasir.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/db.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/open_bill/models/isi_bill.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Open Bill di dalam kerangka kasir SUNGGUHAN: ikon nota hanya di header
/// Dashboard & Kasir (desain), angka lencana, dan Profil → Tutup shift →
/// "Lihat Open Bill" membuka Tagihan Nota.
///
/// Kerangka memakai basis data utama (`db`), jadi berkasnya diarahkan ke
/// folder sementara lewat tiruan path_provider.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    folder = await Directory.systemTemp.createTemp('kerangka_bill');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => folder.path,
        );
  });
  tearDownAll(() async {
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<T> jalan<T>(WidgetTester t, Future<T> Function() f) async =>
      (await t.runAsync(f)) as T;

  Future<void> tunggu(WidgetTester t, [int ms = 200]) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump();
    // Selesaikan animasi lembar/dialog.
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  /// Data bersih tiap test: kasir sari, shift s-1, produk latte, dan
  /// [jumlahBill] bill terbuka.
  Future<void> siapkan(
    WidgetTester t, {
    int jumlahBill = 0,
    List<String> izin = const ['create_transaction', 'open_close_shift'],
  }) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await jalan(t, () async {
      await db.delete(db.openBills).go();
      await db.delete(db.shifts).go();
      await db.delete(db.products).go();
      await db.delete(db.users).go();
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
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: const Value('latte'),
              name: 'Latte',
              price: 18000,
            ),
          );
      for (var i = 1; i <= jumlahBill; i++) {
        await db
            .into(db.openBills)
            .insert(
              OpenBillsCompanion.insert(
                id: Value('b-$i'),
                name: 'Meja $i',
                shiftId: 's-1',
                userId: 'k-1',
                items: kodekanIsiBill([
                  SaleLine(
                    productId: 'latte',
                    productName: 'Latte',
                    qty: 1,
                    priceAtSale: 18000,
                  ),
                ]),
              ),
            );
      }
      await SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'k-1',
          username: 'sari',
          role: 'cashier',
          shiftId: 's-1',
          permissions: izin,
        ),
      );
    });
    addTearDown(SessionManager.instance.clearSession);
    await t.pumpWidget(const MaterialApp(home: KerangkaKasir()));
    await tunggu(t);
  }

  Future<void> keTab(WidgetTester t, String label) async {
    await t.tap(find.text(label).last);
    await tunggu(t);
  }

  final ikonBill = find.byTooltip('Open Bill');

  testWidgets('Ikon Open Bill hanya di header Dashboard dan Kasir', (t) async {
    await siapkan(t, jumlahBill: 2);

    expect(ikonBill, findsOneWidget, reason: 'Dashboard');
    expect(
      find.descendant(of: ikonBill, matching: find.text('2')),
      findsOneWidget,
      reason: 'lencana = jumlah bill terbuka',
    );

    await keTab(t, 'Pengeluaran');
    expect(ikonBill, findsNothing);

    await keTab(t, 'Kasir');
    expect(ikonBill, findsOneWidget);

    await keTab(t, 'Riwayat');
    expect(ikonBill, findsNothing);

    await keTab(t, 'Profil');
    expect(ikonBill, findsNothing);
    await lepas(t);
  });

  testWidgets('Lencana ikut berkurang saat bill dihapus', (t) async {
    await siapkan(t, jumlahBill: 2);
    expect(find.descendant(of: ikonBill, matching: find.text('2')), findsOne);

    await jalan(
      t,
      () => (db.update(db.openBills)..where((b) => b.id.equals('b-1'))).write(
        OpenBillsCompanion(deletedAt: Value(DateTime.now())),
      ),
    );
    await tunggu(t);
    expect(find.descendant(of: ikonBill, matching: find.text('1')), findsOne);
    await lepas(t);
  });

  testWidgets('Tanpa izin Buat Transaksi: ikon Open Bill tidak muncul', (
    t,
  ) async {
    await siapkan(t, jumlahBill: 1, izin: const ['open_close_shift']);
    expect(ikonBill, findsNothing);
    await lepas(t);
  });

  testWidgets('Ketuk ikon di header → Tagihan Nota → bill masuk keranjang', (
    t,
  ) async {
    await siapkan(t, jumlahBill: 1);
    await t.tap(ikonBill);
    await tunggu(t);
    expect(find.text('Tagihan Nota'), findsOneWidget);
    expect(find.text('1 bill terbuka · Rp 18.000'), findsOneWidget);

    await t.tap(find.text('Meja 1'));
    await tunggu(t);
    expect(find.text('Open bill: Meja 1'), findsOneWidget);
    expect(find.text('Perbarui Bill'), findsOneWidget);
    await lepas(t);
  });

  testWidgets(
    'Profil → Tutup shift dengan bill terbuka → Lihat Open Bill membuka '
    'Tagihan Nota',
    (t) async {
      await siapkan(t, jumlahBill: 1);
      await keTab(t, 'Profil');

      await t.tap(find.text('Tutup shift'));
      await tunggu(t, 400);
      expect(find.text('Shift belum bisa ditutup'), findsOneWidget);
      expect(
        find.textContaining('Masih ada 1 open bill yang belum dibayar.'),
        findsOneWidget,
      );

      await t.tap(find.text('Lihat Open Bill'));
      await tunggu(t, 400);
      expect(find.text('Tagihan Nota'), findsOneWidget);
      expect(find.text('Meja 1'), findsOneWidget);
      expect(
        SessionManager.instance.currentSession!.shiftId,
        's-1',
        reason: 'shift tetap berjalan',
      );
      await lepas(t);
    },
  );
}
