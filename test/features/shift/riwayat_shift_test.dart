import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/shift/models/ringkasan_shift.dart';
import 'package:kasir_app/features/shift/pages/detail_shift_page.dart';
import 'package:kasir_app/features/shift/pages/riwayat_shift_page.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riwayat Shift dan Detail Shift (desain).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  final hariIni = DateTime.now();
  final pagi = DateTime(hariIni.year, hariIni.month, hariIni.day, 8);

  Shift shift(DateTime mulai, {DateTime? selesai}) => Shift(
    id: 's',
    userId: 'budi',
    startAt: mulai,
    endAt: selesai,
    updatedAt: mulai,
    syncStatus: 'synced',
  );

  Transaction trx(
    int total, {
    String metode = 'cash',
    String tipe = 'dine_in',
    bool batal = false,
  }) => Transaction(
    id: 't$total$metode$tipe',
    invoiceNo: '',
    createdAt: pagi,
    total: total,
    paymentMethod: metode,
    orderType: tipe,
    updatedAt: pagi,
    deletedAt: batal ? pagi : null,
    syncStatus: 'synced',
  );

  group('RingkasanShift', () {
    final r = RingkasanShift(
      shift: shift(pagi),
      namaKasir: 'budi',
      transaksi: [
        trx(10000),
        trx(15000, tipe: 'delivery'),
        trx(20000, metode: 'qris'),
        // Dari HP yang belum diperbarui: dihitung Dine In.
        trx(5000, tipe: 'take_away'),
        trx(99000, batal: true),
      ],
      pengeluaran: [
        Expense(
          id: 'e1',
          shiftId: 's',
          userId: 'budi',
          description: 'Es',
          amount: 7000,
          category: 'bahan_baku',
          qty: 1,
          createdAt: pagi,
          updatedAt: pagi,
          syncStatus: 'synced',
        ),
        Expense(
          id: 'e2',
          shiftId: 's',
          userId: 'budi',
          description: 'Batal',
          amount: 50000,
          category: 'bahan_baku',
          qty: 1,
          createdAt: pagi,
          updatedAt: pagi,
          deletedAt: pagi,
          syncStatus: 'synced',
        ),
      ],
    );

    test('yang dibatalkan tidak dihitung', () {
      expect(r.jumlahTransaksi, 4);
      expect(r.pendapatan, 50000);
      expect(r.totalPengeluaran, 7000);
      expect((r.jumlahTunai, r.jumlahQris), (3, 1));
      expect((r.jumlahDineIn, r.jumlahDelivery), (3, 1));
    });

    test('rincian Cash/QRIS × Dine In/Delivery', () {
      expect(
        [for (final b in r.rincian) (b.label, b.jumlah, b.total, b.tebal)],
        [
          ('Cash Dine In', 2, 15000, false),
          ('Cash Delivery', 1, 15000, false),
          ('Cash Total', 3, 30000, true),
          ('QRIS Dine In', 1, 20000, false),
          ('QRIS Delivery', 0, 0, false),
          ('QRIS Total', 1, 20000, true),
        ],
      );
    });
  });

  test('durasi dan jam shift', () {
    final selesai = shift(pagi, selesai: pagi.add(const Duration(hours: 7)));
    expect(durasiShift(selesai, DateTime(2099)), '7j 0m');
    expect(jamShift(selesai), '08:00 – 15:00');
    final jalan = shift(pagi);
    expect(
      durasiShift(jalan, pagi.add(const Duration(hours: 2, minutes: 15))),
      '2j 15m',
    );
    expect(jamShift(jalan), '08:00 – sekarang');
  });

  test('label kelompok: Hari ini, Kemarin, lalu tanggal lengkap', () {
    final h = DateTime(2026, 10, 1, 13);
    expect(labelHariShift(DateTime(2026, 10, 1), h), 'Hari ini');
    expect(labelHariShift(DateTime(2026, 9, 30), h), 'Kemarin');
    expect(labelHariShift(DateTime(2026, 9, 29), h), 'Selasa, 29 Sep 2026');
  });

  group('basis data', () {
    late AppDatabase db;
    late ShiftRepository repo;

    Future<void> akun(String id) => db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(id),
            username: id,
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );

    Future<void> bukaShift(
      String id,
      String user,
      DateTime mulai, {
      DateTime? selesai,
    }) => db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: Value(id),
            userId: user,
            startAt: Value(mulai),
            endAt: Value(selesai),
          ),
        );

    Future<void> jual(
      String id,
      String shiftId,
      int total, {
      String metode = 'cash',
      bool batal = false,
    }) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: Value(id),
            shiftId: Value(shiftId),
            total: total,
            paymentMethod: metode,
            createdAt: Value(pagi),
            deletedAt: Value(batal ? pagi : null),
            cancelReason: Value(batal ? 'Pelanggan batal' : null),
            cancelledByUserId: Value(batal ? 'owner' : null),
          ),
        );

    Future<void> belanja(String id, String? shiftId, int amount) => db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: Value(id),
            shiftId: Value(shiftId),
            userId: 'owner',
            description: id,
            amount: amount,
            createdAt: Value(pagi),
          ),
        );

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ShiftRepository(db);
      for (final a in ['owner', 'budi', 'sari']) {
        await akun(a);
      }
      await bukaShift(
        's-budi',
        'budi',
        pagi,
        selesai: pagi.add(const Duration(hours: 7)),
      );
      await bukaShift('s-sari', 'sari', pagi.add(const Duration(hours: 8)));
      await bukaShift('s-lama', 'budi', pagi.subtract(const Duration(days: 3)));
      await jual('t1', 's-budi', 10000);
      await jual('t2', 's-budi', 20000, metode: 'qris');
      await jual('t3', 's-budi', 99000, batal: true);
      await belanja('Es batu', 's-budi', 7000);
      await belanja('Belanja owner', null, 300000);
    });
    tearDown(() => db.close());

    test('periode, urutan terbaru dulu, dan cakupan', () async {
      final semua = await repo.watchRiwayatShift(Periode.hari(hariIni)).first;
      expect(semua.map((r) => r.shift.id), [
        's-sari',
        's-budi',
      ], reason: 'shift 3 hari lalu di luar periode');

      final sendiri = await repo
          .watchRiwayatShift(Periode.hari(hariIni), hanyaUserId: 'budi')
          .first;
      expect(sendiri.map((r) => r.shift.id), ['s-budi']);
    });

    test(
      'isi shift: batal ikut tampil, pengeluaran owner tidak masuk',
      () async {
        final r = (await repo.watchShift('s-budi').first)!;
        expect(r.namaKasir, 'budi');
        expect(r.transaksi, hasLength(3));
        expect(r.pendapatan, 30000);
        expect(r.pengeluaran.map((e) => e.description), ['Es batu']);
      },
    );

    test('ikut berubah saat transaksi baru masuk', () async {
      final aliran = repo.watchShift('s-sari');
      final hasil = <int>[];
      final sub = aliran.listen((r) => hasil.add(r!.pendapatan));
      await pumpEventQueue();
      await jual('t9', 's-sari', 12000);
      await pumpEventQueue();
      await sub.cancel();
      expect(hasil, [0, 12000]);
    });

    /// Kueri pantau drift menyisakan timer nol detik saat halaman dibuang;
    /// lepas halamannya dan habiskan timer itu sebelum test selesai.
    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(Duration.zero);
    }

    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 3600);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> masuk({required bool owner, List<String> izin = const []}) =>
        SessionManager.instance.setSession(
          AuthSession.create(
            userId: owner ? 'owner' : 'budi',
            username: owner ? 'owner' : 'budi',
            role: owner ? 'owner' : 'cashier',
            shiftId: null,
            permissions: izin,
          ),
        );

    testWidgets('Riwayat Shift: ringkasan, kelompok, kartu', (t) async {
      layarHp(t);
      SharedPreferences.setMockInitialValues({});
      await masuk(owner: true);
      addTearDown(SessionManager.instance.clearSession);

      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(home: RiwayatShiftPage(repo: repo)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();

      expect(find.text('Riwayat Shift'), findsOneWidget);
      // Satu di kartu periode, satu judul kelompok.
      expect(find.text('Hari ini'), findsNWidgets(2));
      expect(find.text('2 shift · Rp 30.000'), findsOneWidget);
      expect(find.text('budi'), findsOneWidget);
      expect(find.text('sari'), findsOneWidget);
      expect(find.text('Aktif'), findsOneWidget, reason: 'shift sari');
      expect(find.text('Selesai'), findsOneWidget, reason: 'shift budi');
      expect(find.text('08:00 – 15:00 · 7j 0m'), findsOneWidget);
      expect(
        find.textContaining('Kas awal'),
        findsNothing,
        reason: 'menyusul di fase kasir',
      );
      await lepas(t);
    });

    testWidgets('kasir tanpa izin hanya melihat shift sendiri', (t) async {
      layarHp(t);
      SharedPreferences.setMockInitialValues({});
      await masuk(owner: false);
      addTearDown(SessionManager.instance.clearSession);

      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(home: RiwayatShiftPage(repo: repo)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();

      expect(find.text('budi'), findsOneWidget);
      expect(find.text('sari'), findsNothing);
      await lepas(t);
    });

    testWidgets('Detail Shift: ringkasan, rincian, tab, baris batal', (
      t,
    ) async {
      layarHp(t);
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(
            home: DetailShiftPage(shiftId: 's-budi', repo: repo),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();

      expect(find.text('Detail Shift'), findsOneWidget);
      expect(find.text('08:00 – 15:00'), findsOneWidget);
      expect(find.text('7j 0m'), findsOneWidget);
      expect(find.text('1 / 1 transaksi'), findsOneWidget, reason: 'Cash/QRIS');
      expect(
        find.text('2 / 0 transaksi'),
        findsOneWidget,
        reason: 'Dine In/Delivery',
      );
      expect(find.text('Cash Total'), findsOneWidget);
      expect(find.text('Kas bersih'), findsNothing, reason: 'dihapus desain');

      expect(find.text('Transaksi (3)'), findsOneWidget);
      expect(
        find.textContaining('Dibatalkan · owner', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Alasan: Pelanggan batal'), findsOneWidget);

      await t.tap(find.text('Pengeluaran (1)'));
      await t.pumpAndSettle();
      expect(find.text('Es batu'), findsOneWidget);
      expect(find.text('Belanja owner'), findsNothing);
      await lepas(t);
    });
  });
}
