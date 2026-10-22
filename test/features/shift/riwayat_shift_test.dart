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
import 'package:kasir_app/shared/ui/warna_teras.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riwayat Shift dan Detail Shift (desain).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  final hariIni = DateTime.now();
  final pagi = DateTime(hariIni.year, hariIni.month, hariIni.day, 8);

  Shift shift(DateTime mulai, {DateTime? selesai, int? kasAwal}) => Shift(
    id: 's',
    userId: 'budi',
    startAt: mulai,
    endAt: selesai,
    kasAwal: kasAwal,
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

    test('kas akhir = kas awal + tunai sah − pengeluaran sah', () {
      final berkas = RingkasanShift(
        shift: shift(pagi, kasAwal: 200000),
        namaKasir: 'budi',
        transaksi: r.transaksi,
        pengeluaran: r.pengeluaran,
      );
      // Tunai sah 10.000 + 15.000 + 5.000; QRIS 20.000 dan yang batal
      // 99.000 tidak dihitung; pengeluaran batal 50.000 juga tidak.
      expect(berkas.penjualanTunai, 30000);
      expect(berkas.kasAkhir, 200000 + 30000 - 7000);
    });

    test('kas akhir: shift lama tanpa kas awal = null, bisa minus', () {
      expect(r.kasAkhir, isNull, reason: 'shift sebelum ada kas awal');
      final minus = RingkasanShift(
        shift: shift(pagi, kasAwal: 0),
        namaKasir: 'budi',
        transaksi: const [],
        pengeluaran: r.pengeluaran,
      );
      expect(minus.kasAkhir, -7000);
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
      int? kasAwal,
    }) => db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: Value(id),
            userId: user,
            startAt: Value(mulai),
            endAt: Value(selesai),
            kasAwal: Value(kasAwal),
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
        kasAwal: 200000,
      );
      await bukaShift(
        's-sari',
        'sari',
        pagi.add(const Duration(hours: 8)),
        kasAwal: 50000,
      );
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
      expect(find.text('Kas awal Rp 200.000'), findsOneWidget);
      expect(
        find.text('Kas akhir Rp 203.000'),
        findsOneWidget,
        reason: '200.000 + tunai 10.000 − pengeluaran 7.000',
      );
      expect(find.text('Kas awal Rp 50.000'), findsOneWidget);
      expect(
        find.textContaining('Kas akhir'),
        findsOneWidget,
        reason: 'shift aktif tanpa kas akhir',
      );
      expect(find.textContaining('masih berjalan'), findsNothing);
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
      expect(find.text('Cash / QRIS'), findsNothing, reason: 'keputusan owner');
      expect(
        find.text('2 / 0 transaksi'),
        findsOneWidget,
        reason: 'Dine In/Delivery',
      );
      expect(find.text('Cash Total'), findsOneWidget);
      expect(find.text('Kas bersih'), findsNothing, reason: 'dihapus desain');
      expect(find.text('Uang kas'), findsOneWidget);
      expect(find.text('Rp 200.000'), findsOneWidget, reason: 'kas awal');
      expect(find.text('Kas akhir'), findsOneWidget);
      expect(find.text('Kas di laci saat ini'), findsNothing);
      expect(find.text('Rp 203.000'), findsOneWidget);

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

    Future<void> bukaDetail(WidgetTester t, String id) async {
      layarHp(t);
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(home: DetailShiftPage(shiftId: id, repo: repo)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
    }

    testWidgets('Detail Shift berjalan: "Kas di laci saat ini"', (t) async {
      await jual('t-sari', 's-sari', 25000);
      await belanja('Gas', 's-sari', 5000);
      await bukaDetail(t, 's-sari');
      expect(find.text('Kas di laci saat ini'), findsOneWidget);
      expect(find.text('Kas akhir'), findsNothing);
      expect(find.text('Rp 50.000'), findsOneWidget, reason: 'kas awal');
      expect(find.text('Rp 70.000'), findsOneWidget, reason: '50+25−5 rb');
      await lepas(t);
    });

    testWidgets('Detail Shift lama tanpa kas awal: "–"', (t) async {
      await bukaDetail(t, 's-lama');
      expect(find.text('Uang kas'), findsOneWidget);
      expect(find.text('–'), findsNWidgets(2));
      await lepas(t);
    });

    testWidgets('transaksi & pengeluaran yang masuk setelah shift ditutup '
        'diberi keterangan', (t) async {
      // Shift budi ditutup 15:00; HP yang offline baru menyetor 15:30.
      final telat = pagi.add(const Duration(hours: 7, minutes: 30));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: const Value('t-telat'),
            shiftId: const Value('s-budi'),
            total: 50000,
            paymentMethod: 'cash',
            createdAt: Value(telat),
          ));
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: const Value('e-telat'),
            shiftId: const Value('s-budi'),
            userId: 'budi',
            description: 'Es telat',
            amount: 4000,
            createdAt: Value(telat),
          ));
      await bukaDetail(t, 's-budi');
      expect(find.text('Masuk setelah shift ditutup'), findsOneWidget,
          reason: 'hanya transaksi 15:30, bukan yang pagi');
      await t.tap(find.text('Pengeluaran (2)'));
      await t.pumpAndSettle();
      expect(find.text('Masuk setelah shift ditutup'), findsOneWidget,
          reason: 'hanya Es telat');
      await lepas(t);
    });

    test('masukSetelahTutup: shift berjalan tidak pernah', () async {
      final berjalan = (await repo.watchShift('s-sari').first)!;
      expect(berjalan.masukSetelahTutup(DateTime(2099)), isFalse);
      final tutup = (await repo.watchShift('s-budi').first)!;
      final jamTutup = tutup.shift.endAt!;
      expect(tutup.masukSetelahTutup(jamTutup), isFalse);
      expect(
        tutup.masukSetelahTutup(jamTutup.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    testWidgets('Kas minus tampil merah', (t) async {
      await bukaShift('s-minus', 'budi', pagi, kasAwal: 0);
      await belanja('Galon', 's-minus', 30000);
      await bukaDetail(t, 's-minus');
      final teks = t.widget<Text>(find.text('-Rp 30.000'));
      expect(teks.style!.color, WarnaTeras.merah);
      await lepas(t);
    });
  });
}
