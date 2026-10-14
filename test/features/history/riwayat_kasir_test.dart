import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/history/history_page.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riwayat kasir (desain): cari · chip metode · per hari berpita oranye yang
/// bisa dilipat. Tanpa izin hanya shift berjalan; dengan izin Lihat Riwayat
/// Lengkap semua transaksi miliknya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  final kini = DateTime.now();
  final kemarin = kini.subtract(const Duration(days: 1));

  Future<void> masuk({String? shiftId = 's-1', bool riwayat = false}) =>
      SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'k-1',
          username: 'sari',
          role: 'cashier',
          shiftId: shiftId,
          permissions: ['create_transaction', if (riwayat) 'view_history'],
        ),
      );

  Future<void> jual(
    String id,
    String shift,
    String menu,
    int qty, {
    String metode = 'cash',
    bool batal = false,
    DateTime? pada,
  }) async {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: Value(id),
            invoiceNo: Value('TRX/$id'),
            total: qty * 10000,
            paymentMethod: metode,
            cashierUserId: const Value('k-1'),
            shiftId: Value(shift),
            createdAt: Value(pada ?? kini),
            deletedAt: Value(batal ? kini : null),
            cancelReason: Value(batal ? 'Salah input' : null),
          ),
        );
    await db
        .into(db.transactionItems)
        .insert(
          TransactionItemsCompanion.insert(
            transactionId: id,
            productId: 'p-$menu',
            productName: Value(menu),
            qty: qty,
            priceAtSale: 10000,
            subtotal: qty * 10000,
          ),
        );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
          ShiftsCompanion.insert(
            id: const Value('s-lama'),
            userId: 'k-1',
            startAt: Value(kemarin.subtract(const Duration(hours: 8))),
            endAt: Value(kemarin),
          ),
        );
    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: const Value('s-1'),
            userId: 'k-1',
            startAt: Value(kini.subtract(const Duration(hours: 1))),
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

  Future<void> tunggu(WidgetTester t) async {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await t.pump();
  }

  Future<void> buka(WidgetTester t) async {
    layarHp(t);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryPage(
            repo: SalesRepository(db),
            repoShift: ShiftRepository(db),
          ),
        ),
      ),
    );
    await tunggu(t);
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  Future<void> isiData(WidgetTester t, {bool riwayat = false}) =>
      t.runAsync(() async {
        await jual('A1', 's-1', 'Latte', 2);
        await jual('A2', 's-1', 'Teh', 1, metode: 'qris');
        await jual('A3', 's-1', 'Kue', 9, batal: true);
        await jual('L1', 's-lama', 'Roti', 3, pada: kemarin);
        await masuk(riwayat: riwayat);
      });

  testWidgets('tanpa izin: hanya shift berjalan, per hari, chip & cari', (
    t,
  ) async {
    await isiData(t);
    await buka(t);
    expect(find.text('3 Transaksi'), findsOneWidget);
    expect(find.text('Rp 30.000'), findsOneWidget, reason: 'tanpa yang batal');
    expect(find.text('TRX/L1'), findsNothing, reason: 'shift lama');
    expect(find.text('Transaksi QRIS'), findsOneWidget);
    expect(find.textContaining('Dibatalkan'), findsOneWidget);
    expect(
      find.byTooltip('Batalkan'),
      findsNWidgets(2),
      reason: 'milik sendiri di shift berjalan, yang belum batal',
    );

    await t.tap(find.text('QRIS'));
    await t.pump();
    expect(find.text('TRX/A2'), findsOneWidget);
    expect(find.text('TRX/A1'), findsNothing);
    await t.tap(find.text('Semua'));
    await t.pump();

    await t.enterText(find.byType(TextField), 'latte');
    await tunggu(t);
    expect(find.text('TRX/A1'), findsOneWidget);
    expect(find.text('TRX/A2'), findsNothing);

    await t.enterText(find.byType(TextField), 'tidak ada');
    await tunggu(t);
    expect(find.text('Riwayat tidak ditemukan'), findsOneWidget);
    await lepas(t);
  });

  testWidgets('dengan izin: hari-hari lama ikut, tiap hari bisa dilipat', (
    t,
  ) async {
    await isiData(t, riwayat: true);
    await buka(t);
    expect(find.text('TRX/L1'), findsOneWidget);
    expect(find.text('1 Transaksi'), findsOneWidget);

    await t.tap(find.text('1 Transaksi'));
    await t.pump();
    expect(find.text('TRX/L1'), findsNothing, reason: 'hari kemarin dilipat');
    expect(find.text('TRX/A1'), findsOneWidget, reason: 'hari ini tetap');
    await lepas(t);
  });

  testWidgets('ketuk baris membuka struk', (t) async {
    await isiData(t);
    await buka(t);
    await t.tap(find.text('TRX/A1'));
    await tunggu(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Detail Transaksi'), findsOneWidget);
    await lepas(t);
  });

  testWidgets('tanpa shift & tanpa izin: kartu desain + rekap terakhir', (
    t,
  ) async {
    await t.runAsync(() => masuk(shiftId: null));
    await buka(t);
    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(find.text('Lihat rekap shift terakhir'), findsOneWidget);
    await lepas(t);
  });

  testWidgets('shift berjalan tanpa transaksi', (t) async {
    await t.runAsync(() => masuk());
    await buka(t);
    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(
      find.text('Transaksi di shift ini akan muncul di sini.'),
      findsOneWidget,
    );
    expect(find.text('Lihat rekap shift terakhir'), findsNothing);
    await lepas(t);
  });
}
