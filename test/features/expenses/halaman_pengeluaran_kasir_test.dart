import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/expenses_page.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/shift/pages/detail_shift_page.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Halaman Pengeluaran kasir (desain) + "Riwayat Pengeluaran" yang tetap
/// dipertahankan untuk kasir berizin Lihat Riwayat Lengkap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  final hariIni = DateTime.now();

  Future<void> masuk({String? shiftId, bool riwayat = true}) =>
      SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'k-1',
          username: 'sari',
          role: 'cashier',
          shiftId: shiftId,
          permissions: ['open_close_shift', if (riwayat) 'view_history'],
        ),
      );

  Future<void> shift(String id, {required DateTime mulai, DateTime? selesai}) =>
      db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: Value(id),
              userId: 'k-1',
              startAt: Value(mulai),
              endAt: Value(selesai),
            ),
          );

  Future<void> keluar(
    String id,
    String shiftId,
    String nama,
    int nominal, {
    bool batal = false,
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: Value(id),
          shiftId: Value(shiftId),
          userId: 'k-1',
          description: nama,
          amount: nominal,
          deletedAt: Value(batal ? hariIni : null),
          cancelReason: Value(batal ? 'Salah catat' : null),
        ),
      );

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
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  void layarHp(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> buka(WidgetTester t) async {
    layarHp(t);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpensesPage(
            repo: ExpenseRepository(db),
            repoShift: ShiftRepository(db),
          ),
        ),
      ),
    );
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await t.pump();
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  testWidgets('shift berjalan: total tanpa yang dibatalkan, rincian, '
      'tombol tambah', (t) async {
    await t.runAsync(() async {
      await shift('s-1', mulai: hariIni.subtract(const Duration(hours: 1)));
      await keluar('e-1', 's-1', 'Es batu', 5000);
      await keluar('e-2', 's-1', 'Gas', 25000);
      await keluar('e-3', 's-1', 'Salah', 9000, batal: true);
      await masuk(shiftId: 's-1');
    });
    await buka(t);
    expect(find.text('Shift Aktif'), findsOneWidget);
    expect(find.text('Rp 30.000'), findsOneWidget);
    expect(find.text('2 Transaksi'), findsOneWidget);
    expect(find.text('Waktu Shift'), findsOneWidget);
    expect(find.text('Rincian Pengeluaran'), findsOneWidget);
    expect(find.text('-Rp 30.000'), findsOneWidget, reason: 'total hari');
    expect(find.text('Gas'), findsOneWidget);
    expect(find.textContaining('Dibatalkan'), findsOneWidget);
    expect(find.byTooltip('Catat pengeluaran'), findsOneWidget);

    await t.tap(find.text('Cek Rekapitulasi Shift'));
    await t.pumpAndSettle();
    expect(find.byType(DetailShiftPage), findsOneWidget);
    await lepas(t);
  });

  testWidgets('shift berjalan tanpa pengeluaran', (t) async {
    await t.runAsync(() async {
      await shift('s-1', mulai: hariIni);
      await masuk(shiftId: 's-1');
    });
    await buka(t);
    expect(find.text('Belum ada pengeluaran di shift ini'), findsOneWidget);
    expect(find.text('Rp 0'), findsOneWidget);
    await lepas(t);
  });

  testWidgets('tanpa shift: kartu desain, rekap terakhir, tanpa tombol '
      'tambah', (t) async {
    await t.runAsync(() async {
      await shift(
        's-lama',
        mulai: hariIni.subtract(const Duration(days: 1, hours: 8)),
        selesai: hariIni.subtract(const Duration(days: 1)),
      );
      await masuk();
    });
    await buka(t);
    expect(find.text('Belum ada pengeluaran'), findsOneWidget);
    expect(find.text('Lihat rekap shift terakhir'), findsOneWidget);
    expect(find.byTooltip('Catat pengeluaran'), findsNothing);
    await lepas(t);
  });

  testWidgets('riwayat pengeluaran shift lama: total, buka-tutup, ikut '
      'berubah', (t) async {
    await t.runAsync(() async {
      await shift(
        's-lama',
        mulai: hariIni.subtract(const Duration(days: 1, hours: 8)),
        selesai: hariIni.subtract(const Duration(days: 1)),
      );
      await shift(
        's-kosong',
        mulai: hariIni.subtract(const Duration(days: 2, hours: 8)),
        selesai: hariIni.subtract(const Duration(days: 2)),
      );
      await shift('s-1', mulai: hariIni);
      await keluar('e-1', 's-lama', 'Plastik', 7000);
      await keluar('e-2', 's-1', 'Es batu', 5000);
      await masuk(shiftId: 's-1');
    });
    await buka(t);
    expect(find.text('Riwayat Pengeluaran'), findsOneWidget);
    expect(find.text('-Rp 7.000'), findsOneWidget);
    expect(
      find.text('1 transaksi'),
      findsOneWidget,
      reason: 'shift kosong dan shift aktif tidak ikut',
    );
    expect(find.text('Plastik'), findsNothing, reason: 'masih tertutup');

    await t.tap(find.text('-Rp 7.000'));
    await t.pump();
    expect(find.text('Plastik'), findsOneWidget);

    // Pengeluaran baru di shift lama tiba lewat sinkron.
    await t.runAsync(() => keluar('e-3', 's-lama', 'Lakban', 3000));
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await t.pump();
    expect(find.text('-Rp 10.000'), findsOneWidget);
    await lepas(t);
  });

  testWidgets('tanpa izin Lihat Riwayat Lengkap: riwayat tidak tampil', (
    t,
  ) async {
    await t.runAsync(() async {
      await shift('s-1', mulai: hariIni);
      await masuk(shiftId: 's-1', riwayat: false);
    });
    await buka(t);
    expect(find.text('Shift Aktif'), findsOneWidget);
    expect(find.text('Riwayat Pengeluaran'), findsNothing);
    await lepas(t);
  });
}
