import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/report/pages/laporan_page.dart';
import 'package:kasir_app/features/report/repositories/laporan_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  late DateTime sekarang;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: const Value('o'),
        username: 'owner',
        pinHash: 'h',
        salt: 's',
        role: 'owner',
      ),
    );
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'o',
        username: 'owner',
        role: 'owner',
        shiftId: null,
        permissions: const [],
      ),
    );
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> jual(DateTime pada, {DateTime? batal}) =>
      db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: const Value('t1'),
          invoiceNo: const Value('CS/UJI/1'),
          total: 5000,
          paymentMethod: 'qris',
          createdAt: Value(pada),
          deletedAt: Value(batal),
          cancelledByUserId: Value(batal == null ? null : 'o'),
        ),
      );

  Future<void> jalan(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> buka(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LaporanPage(repo: LaporanRepository(db), jam: () => sekarang),
        ),
      ),
    );
    await jalan(t);
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('review D5: tanggal dan jam sama-sama waktu pembatalan', (
    t,
  ) async {
    sekarang = DateTime(2026, 11, 2, 9);
    await t.runAsync(
      () => jual(
        DateTime(2026, 11, 1, 23, 50),
        batal: DateTime(2026, 11, 2, 8, 15),
      ),
    );
    sekarang = DateTime(2026, 11, 1, 23, 55);
    await buka(t);
    expect(find.textContaining('02/11 · 08:15'), findsOneWidget);
    expect(find.textContaining('01/11 · 08:15'), findsNothing);
    await lepas(t);
  });

  testWidgets('review D4: hari berganti saat memilih format → label file '
      'tetap hari saat Unduh ditekan', (t) async {
    sekarang = DateTime(2026, 10, 1, 23, 59, 50);
    await t.runAsync(() => jual(DateTime(2026, 10, 1, 10)));
    await buka(t);

    await t.tap(find.text('Unduh Laporan'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Download Laporan'), findsOneWidget);

    // Lewat tengah malam: pintasan "Hari ini" pindah ke 2 Oktober.
    sekarang = DateTime(2026, 10, 2, 0, 0, 1);
    await t.pump(const Duration(seconds: 12));
    await jalan(t);

    await t.tap(find.text('Excel'));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('Download'));
    await t.pump();
    for (var i = 0; i < 40 && find.text('Laporan siap').evaluate().isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('01/10/2026'), findsWidgets);
    expect(find.textContaining('Laporan_01102026'), findsOneWidget);
    expect(find.textContaining('02/10/2026'), findsNothing);

    await t.pump(const Duration(seconds: 5));
    await lepas(t);
  });
}
