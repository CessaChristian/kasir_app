import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/dashboard/pages/dasbor_kasir_page.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/features/profil/pages/profil_kasir_page.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/shift/models/format_shift.dart';
import 'package:kasir_app/features/shift/models/produk_laris.dart';
import 'package:kasir_app/features/shift/pengelola_shift.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/features/shift/widgets/dialog_buka_shift.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/tombol_lembar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Shift dibuka manual dengan kas awal (v37): login ≠ buka shift, tanpa shift
/// tidak bisa berjualan, dan Produk Paling Laris dihitung per minggu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  late ShiftRepository repo;

  Future<void> masuk({
    String? shiftId,
    List<String> izin = const ['open_close_shift', 'create_transaction'],
  }) => SessionManager.instance.setSession(
    AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: shiftId,
      permissions: izin,
    ),
  );

  Future<void> produk(String id, String nama, {DateTime? dihapus}) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: Value(id),
          name: nama,
          price: 10000,
          deletedAt: Value(dihapus),
        ),
      );

  /// Transaksi langsung ke tabel (tanpa createSale) supaya tanggalnya bisa
  /// diatur.
  Future<void> jual(
    String id,
    String idProduk,
    int qty, {
    required DateTime pada,
    String shiftId = 's-1',
    bool batal = false,
  }) async {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: Value(id),
            total: qty * 10000,
            paymentMethod: 'cash',
            shiftId: Value(shiftId),
            createdAt: Value(pada),
            deletedAt: Value(batal ? pada : null),
          ),
        );
    await db
        .into(db.transactionItems)
        .insert(
          TransactionItemsCompanion.insert(
            transactionId: id,
            productId: idProduk,
            productName: Value('struk-$idProduk'),
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
    repo = ShiftRepository(db);
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
    await masuk();
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test('migrasi v36 → v37: kolom kas_awal ada, shift lama kosong', () async {
    final folder = Directory.systemTemp.createTempSync('uji_v37');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v36.sqlite';
    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama
        .into(lama.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    await lama
        .into(lama.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: const Value('s-lama'),
            userId: 'k-1',
            syncStatus: const Value('synced'),
          ),
        );
    await lama.close();
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE shifts DROP COLUMN kas_awal');
    mentah.execute('PRAGMA user_version = 36');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baru.close);
    final s = await baru.select(baru.shifts).getSingle();
    expect(s.kasAwal, isNull);
    expect(s.syncStatus, 'synced');
  });

  group('buka & tutup shift', () {
    test('buka: kas awal tersimpan (boleh 0), ikut dikirim', () async {
      final id = await repo.bukaShift(userId: 'k-1', kasAwal: 0);
      final s = await repo.getById(id);
      expect((s!.kasAwal, s.endAt, s.syncStatus), (0, null, 'pending'));
    });

    test('buka: kas awal negatif ditolak', () async {
      expect(
        () => repo.bukaShift(userId: 'k-1', kasAwal: -1),
        throwsArgumentError,
      );
    });

    test('buka saat masih ada shift terbuka: shift lama dipakai', () async {
      final a = await repo.bukaShift(userId: 'k-1', kasAwal: 100000);
      final b = await repo.bukaShift(userId: 'k-1', kasAwal: 200000);
      expect(b, a);
      expect(await db.select(db.shifts).get(), hasLength(1));
      expect((await repo.getById(a))!.kasAwal, 100000);
    });

    test('tanpa izin Buka & Tutup Shift: buka dan tutup ditolak', () async {
      final id = await repo.bukaShift(userId: 'k-1', kasAwal: 0);
      await masuk(izin: const ['create_transaction']);
      expect(() => repo.bukaShift(userId: 'k-1', kasAwal: 0), throwsStateError);
      expect(() => repo.tutupShift(id), throwsStateError);
    });

    test('PengelolaShift: buka mengisi sesi, tutup mengosongkan', () async {
      final p = PengelolaShift(db);
      expect(await p.buka(50000), isFalse);
      final id = SessionManager.instance.currentSession!.shiftId;
      expect(id, isNotNull);
      expect((await repo.getById(id!))!.kasAwal, 50000);

      await p.tutup();
      expect(SessionManager.instance.currentSession!.shiftId, isNull);
      expect(
        SessionManager.instance.isLoggedIn,
        isTrue,
        reason: 'menutup shift tidak mengeluarkan kasir dari akun',
      );
      final s = await repo.getById(id);
      expect((s!.endAt != null, s.syncStatus), (true, 'pending'));
    });

    test('halangan menutup: offline dan dipegang HP lain', () async {
      expect(
        await PengelolaShift(db, online: () => false).halanganMenutup('s-1'),
        contains('Butuh internet'),
      );
      expect(
        await PengelolaShift(
          db,
          online: () => true,
          pemegangLain: (_) async => [
            (nama: 'Emulator 2', diam: const Duration(minutes: 3)),
          ],
        ).halanganMenutup('s-1'),
        'Shift ini masih dipakai di Emulator 2 (aktif 3 menit lalu). Tutup '
        'shift dari perangkat itu. Kalau perangkat itu sudah tidak dipakai, '
        'shift bisa ditutup sekitar 12 menit lagi.',
      );
      expect(
        await PengelolaShift(
          db,
          online: () => true,
          pemegangLain: (_) async => const [],
        ).halanganMenutup('s-1'),
        isNull,
      );
      expect(
        await PengelolaShift(
          db,
          online: () => true,
          pemegangLain: (_) async => throw Exception('putus'),
        ).halanganMenutup('s-1'),
        contains('Tidak bisa memastikan'),
        reason: '"tidak tahu" tidak boleh dianggap "tidak ada yang memegang"',
      );
    });

    test('pesan pemegang: beberapa perangkat, baru saja aktif', () {
      expect(
        PengelolaShift.pesanDipegang([
          (nama: 'HP A', diam: const Duration(seconds: 20)),
          (nama: 'HP B', diam: const Duration(minutes: 7, seconds: 30)),
          (nama: 'HP C', diam: const Duration(minutes: 14, seconds: 50)),
        ]),
        'Shift ini masih dipakai di HP A (aktif baru saja), HP B (aktif 7 '
        'menit lalu) dan HP C (aktif 14 menit lalu). Tutup shift dari '
        'perangkat-perangkat itu. Kalau perangkat-perangkat itu sudah tidak '
        'dipakai, shift bisa ditutup sekitar 15 menit lagi.',
        reason: 'sisa waktu mengikuti perangkat yang PALING BARU aktif',
      );
      expect(
        PengelolaShift.pesanDipegang([
          (nama: 'HP A', diam: const Duration(minutes: 14, seconds: 50)),
        ]),
        endsWith('sekitar 1 menit lagi.'),
      );
    });

    test('tanpa shift tidak bisa berjualan', () async {
      await produk('p-1', 'Es Teh');
      expect(
        () => db.createSale(
          transactionId: 't-1',
          lines: [
            SaleLine(
              productId: 'p-1',
              productName: 'Es Teh',
              qty: 1,
              priceAtSale: 10000,
            ),
          ],
          paymentMethod: 'qris',
          orderType: 'dine_in',
          cashierUserId: 'k-1',
          kodePerangkat: 'TEST',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'pesan',
            contains('Buka shift'),
          ),
        ),
      );
    });
  });

  group('sinkron kas_awal', () {
    test('ikut dikirim; server tanpa kolom tidak mengosongkan', () async {
      final terkirim = <Map<String, dynamic>>[];
      var server = <Map<String, dynamic>>[];
      final mesin = SyncEngine(db)
        ..penarikUntukTest = ((tabel, kolom, sejak, setelah, batas) async =>
            tabel == 'shifts' ? server : const <Map<String, dynamic>>[])
        ..pengirimUntukTest = (tabel, baris) async {
          if (tabel == 'shifts') terkirim.addAll(baris);
        };
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s-1'),
              userId: 'k-1',
              kasAwal: const Value(150000),
              updatedAt: Value(DateTime(2026, 10, 1)),
            ),
          );
      await mesin.dorongSemua();
      expect(terkirim.single['kas_awal'], 150000);

      final cap = DateTime.utc(2026, 10, 2).toIso8601String();
      server = [
        {
          'id': 's-1',
          'user_id': 'k-1',
          'start_at': cap,
          'end_at': cap,
          'updated_at': cap,
          'deleted_at': null,
          'server_urut': cap,
        },
      ];
      await mesin.tarikTabel('shifts');
      final s = await repo.getById('s-1');
      expect(s!.endAt, isNotNull, reason: 'baris server memang diterima');
      expect(s.kasAwal, 150000);
    });
  });

  test('rentang shift: hari ini, hari lain, dan melewati tengah malam', () {
    final kini = DateTime(2026, 10, 13, 22);
    expect(
      rentangShift(DateTime(2026, 10, 13, 13, 26), null, kini),
      '13:26–sekarang',
    );
    expect(
      rentangShift(
        DateTime(2026, 10, 1, 13, 26),
        DateTime(2026, 10, 1, 21, 4),
        kini,
      ),
      '1 Okt 13:26–21:04',
    );
    expect(
      rentangShift(
        DateTime(2026, 10, 2, 20, 39),
        DateTime(2026, 10, 3, 18, 55),
        kini,
      ),
      '2 Okt 20:39–3 Okt 18:55',
      reason: 'jam selesai tidak boleh tampak lebih awal dari jam mulai',
    );
  });

  group('produk paling laris', () {
    test('minggu dimulai Senin 00.00', () {
      expect(awalMinggu(DateTime(2026, 10, 14, 15)), DateTime(2026, 10, 12));
      expect(awalMinggu(DateTime(2026, 10, 12, 0, 1)), DateTime(2026, 10, 12));
      expect(awalMinggu(DateTime(2026, 10, 18, 23)), DateTime(2026, 10, 12));
    });

    test('hanya minggu ini, tanpa yang dibatalkan dan produk terhapus, '
        'paling banyak dulu, maksimal 4', () async {
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'),
          );
      for (final (id, nama) in const [
        ('kopi', 'Kopi'),
        ('teh', 'Teh'),
        ('roti', 'Roti'),
        ('mie', 'Mie'),
        ('nasi', 'Nasi'),
      ]) {
        await produk(id, nama);
      }
      await produk('lama', 'Lama', dihapus: DateTime(2026, 10, 13));
      final senin = DateTime(2026, 10, 12);
      await jual('t1', 'kopi', 5, pada: DateTime(2026, 10, 13));
      await jual('t2', 'teh', 3, pada: DateTime(2026, 10, 12, 0, 1));
      await jual('t3', 'roti', 3, pada: DateTime(2026, 10, 14));
      await jual('t4', 'mie', 2, pada: DateTime(2026, 10, 14));
      await jual('t5', 'nasi', 1, pada: DateTime(2026, 10, 14));
      // Minggu lalu, dibatalkan, dan produk terhapus: tidak dihitung.
      await jual('t6', 'nasi', 50, pada: DateTime(2026, 10, 11, 23, 59));
      await jual('t7', 'mie', 50, pada: DateTime(2026, 10, 14), batal: true);
      await jual('t8', 'lama', 50, pada: DateTime(2026, 10, 14));

      final hasil = await repo.watchProdukLarisMinggu(senin).first;
      expect(
        [for (final p in hasil) '${p.nama} ${p.terjual}'],
        ['Kopi 5', 'Roti 3', 'Teh 3', 'Mie 2'],
      );
      expect(
        await repo.watchProdukLarisMinggu(DateTime(2026, 10, 19)).first,
        isEmpty,
        reason: 'Senin berikutnya mulai dari nol',
      );
    });

    test(
      'terlaris shift ikut menampilkan produk terhapus (nama struk)',
      () async {
        await db
            .into(db.shifts)
            .insert(
              ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'),
            );
        await produk('kopi', 'Kopi');
        await jual('t1', 'kopi', 2, pada: DateTime(2026, 10, 13));
        await jual('t2', 'hilang', 4, pada: DateTime(2026, 10, 13));
        final hasil = await repo.watchTerlarisShift('s-1').first;
        expect(
          [for (final p in hasil) '${p.nama} ${p.terjual}'],
          ['struk-hilang 4', 'Kopi 2'],
        );
      },
    );
  });

  group('halaman', () {
    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> tunggu(WidgetTester t) async {
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

    Future<void> siapkanShift(WidgetTester t, {bool selesai = false}) =>
        t.runAsync(() async {
          await db
              .into(db.shifts)
              .insert(
                ShiftsCompanion.insert(
                  id: const Value('s-1'),
                  userId: 'k-1',
                  startAt: Value(
                    DateTime.now().subtract(
                      const Duration(hours: 2, minutes: 15),
                    ),
                  ),
                  kasAwal: const Value(150000),
                ),
              );
          await produk('kopi', 'Kopi Susu');
          await jual('t1', 'kopi', 2, pada: DateTime.now());
          await db.addExpense(
            shiftId: 's-1',
            userId: 'k-1',
            description: 'Es batu',
            amount: 5000,
          );
          // Ditutup SESUDAH dicatat: shift yang sudah tutup menolak
          // pengeluaran baru.
          if (selesai) {
            await (db.update(db.shifts)..where((s) => s.id.equals('s-1')))
                .write(ShiftsCompanion(endAt: Value(DateTime.now())));
          }
          await masuk(shiftId: selesai ? null : 's-1');
        });

    testWidgets('dashboard shift berjalan: angka, kas awal, laris → '
        'keranjang', (t) async {
      layarHp(t);
      await siapkanShift(t);
      final keranjang = Keranjang();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DasborKasirPage(keranjang: keranjang, repo: repo),
          ),
        ),
      );
      await tunggu(t);
      expect(find.text('2j 15m'), findsOneWidget);
      expect(find.text('Rp 20.000'), findsOneWidget);
      expect(find.text('Rp 150.000'), findsOneWidget);
      expect(find.text('Rp 5.000'), findsOneWidget);
      expect(find.text('Tunai: 1 transaksi'), findsOneWidget);
      expect(find.text('Terjual 2'), findsOneWidget);

      await t.tap(find.text('Kopi Susu'));
      await t.pump();
      expect(keranjang.baris.single.productName, 'Kopi Susu');
      expect(find.text('Kopi Susu ditambahkan ke keranjang'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('dashboard shift selesai: ringkasan, terlaris, tidak bisa '
        'menambah ke keranjang', (t) async {
      layarHp(t);
      await siapkanShift(t, selesai: true);
      final keranjang = Keranjang();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DasborKasirPage(keranjang: keranjang, repo: repo),
          ),
        ),
      );
      await tunggu(t);
      expect(find.text('Shift selesai'), findsOneWidget);
      expect(find.text('Buka Shift Baru'), findsOneWidget);
      expect(find.text('Terlaris di Shift Terakhir'), findsOneWidget);
      expect(find.text('2 terjual'), findsOneWidget);

      await t.tap(find.text('Terjual 2'));
      await t.pump();
      expect(keranjang.isEmpty, isTrue);
      expect(
        find.text('Buka shift dulu untuk mulai berjualan'),
        findsOneWidget,
      );
      await lepas(t);
    });

    testWidgets('dashboard belum pernah shift: kosong & Buka Shift', (t) async {
      layarHp(t);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DasborKasirPage(keranjang: Keranjang(), repo: repo),
          ),
        ),
      );
      await tunggu(t);
      expect(find.text('Belum buka shift'), findsOneWidget);
      expect(find.text('Buka Shift'), findsOneWidget);
      expect(find.text('Belum ada produk terjual'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('dialog Buka shift: wajib diisi, nominal cepat, boleh 0', (
      t,
    ) async {
      layarHp(t);
      int? hasil = -1;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  hasil = await tampilkanDialogBukaShift(c, nama: 'sari'),
              child: const Text('buka'),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      await t.tap(find.text('Buka Shift'));
      await t.pump();
      expect(find.text('Isi uang kas awal (boleh 0)'), findsOneWidget);

      await t.tap(find.text('200rb'));
      await t.pump();
      expect(find.text('200.000'), findsOneWidget);
      await t.tap(find.text('Buka Shift'));
      await t.pumpAndSettle();
      expect(hasil, 200000);

      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '0');
      await t.tap(find.text('Buka Shift'));
      await t.pumpAndSettle();
      expect(hasil, 0);
    });

    testWidgets('Profil kasir: kartu shift, menu sesuai izin, dialog tutup', (
      t,
    ) async {
      layarHp(t);
      await siapkanShift(t);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfilKasirPage(
              repo: repo,
              repoBill: OpenBillRepository(db),
              pengelola: PengelolaShift(
                db,
                online: () => true,
                pemegangLain: (_) async => const [],
              ),
            ),
          ),
        ),
      );
      await tunggu(t);
      expect(find.text('Shift aktif'), findsOneWidget);
      expect(find.textContaining('· 1 transaksi'), findsOneWidget);
      expect(find.text('Riwayat Shift'), findsOneWidget);
      expect(find.text('Produk'), findsNothing, reason: 'tanpa izin');
      expect(find.text('Laporan'), findsNothing);

      await t.tap(find.text('Tutup shift'));
      await tunggu(t);
      await t.pumpAndSettle();
      expect(find.text('Tutup shift sekarang?'), findsOneWidget);
      expect(find.textContaining('1 transaksi · Rp 20.000.'), findsOneWidget);
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(SessionManager.instance.currentSession!.shiftId, 's-1');
      await lepas(t);
    });

    group('tombol Tutup shift', () {
      /// Profil kasir; setiap pertanyaan "siapa lagi yang memegang shift"
      /// menunggu sampai test menjawabnya lewat Completer yang dikembalikan.
      Future<List<Completer<List<PemegangShift>>>> bukaProfil(
        WidgetTester t,
      ) async {
        layarHp(t);
        await siapkanShift(t);
        final pertanyaan = <Completer<List<PemegangShift>>>[];
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfilKasirPage(
                repo: repo,
                repoBill: OpenBillRepository(db),
                pengelola: PengelolaShift(
                  db,
                  online: () => true,
                  pemegangLain: (_) {
                    final c = Completer<List<PemegangShift>>();
                    pertanyaan.add(c);
                    return c.future;
                  },
                ),
              ),
            ),
          ),
        );
        await tunggu(t);
        return pertanyaan;
      }

      testWidgets('kartu memuat langsung muncul, ketukan beruntun diabaikan', (
        t,
      ) async {
        final pertanyaan = await bukaProfil(t);
        for (var i = 0; i < 3; i++) {
          await t.tap(find.text('Tutup shift'), warnIfMissed: false);
        }
        await t.pump();
        expect(find.text('Memeriksa shift…'), findsOneWidget,
            reason: 'tanda muncul SEBELUM server menjawab');
        expect(find.text('Tutup shift sekarang?'), findsNothing);
        expect(pertanyaan, hasLength(1), reason: 'satu proses saja');

        pertanyaan.single.complete(const []);
        await tunggu(t);
        await t.pumpAndSettle();
        expect(find.text('Memeriksa shift…'), findsNothing);
        expect(find.text('Tutup shift sekarang?'), findsOneWidget);
        await t.tap(find.text('Batal'));
        await t.pumpAndSettle();

        // Sesudah selesai, tombolnya bisa dipakai lagi.
        await t.tap(find.text('Tutup shift'));
        await t.pump();
        expect(pertanyaan, hasLength(2));
        pertanyaan.last.complete(const []);
        await tunggu(t);
        await t.pumpAndSettle();
        await t.tap(find.text('Batal'));
        await t.pumpAndSettle();
        await lepas(t);
      });

      testWidgets('masih dipegang perangkat lain: dialog satu tombol, bukan '
          'toast', (t) async {
        final pertanyaan = await bukaProfil(t);
        await t.tap(find.text('Tutup shift'));
        await t.pump();
        pertanyaan.single.complete([
          (nama: 'Emulator 2', diam: const Duration(minutes: 3)),
        ]);
        await tunggu(t);
        await t.pumpAndSettle();
        expect(find.text('Shift belum bisa ditutup'), findsOneWidget);
        expect(find.textContaining('masih dipakai di Emulator 2'),
            findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TombolLembar),
          ),
          findsOneWidget,
          reason: 'pemberitahuan, bukan pertanyaan — cukup satu tombol',
        );
        expect(find.text('Tutup shift sekarang?'), findsNothing);
        await t.tap(find.text('Mengerti'));
        await t.pumpAndSettle();
        expect(find.text('Shift belum bisa ditutup'), findsNothing);
        expect(SessionManager.instance.currentSession!.shiftId, 's-1');
        await lepas(t);
      });

      testWidgets('diperiksa ulang sesudah dikonfirmasi; tanpa halangan '
          'shiftnya ditutup', (t) async {
        final pertanyaan = await bukaProfil(t);
        await t.tap(find.text('Tutup shift'));
        await t.pump();
        pertanyaan.single.complete(const []);
        await tunggu(t);
        await t.pumpAndSettle();

        // Perangkat lain masuk ke shift ini selagi dialognya terbuka.
        await t.tap(find.text('Tutup Shift'));
        await t.pump();
        expect(find.text('Menutup shift…'), findsOneWidget);
        expect(pertanyaan, hasLength(2));
        pertanyaan.last.complete([
          (nama: 'HP Kasir', diam: Duration.zero),
        ]);
        await tunggu(t);
        await t.pumpAndSettle();
        expect(find.textContaining('masih dipakai di HP Kasir'),
            findsOneWidget);
        expect(SessionManager.instance.currentSession!.shiftId, 's-1');
        await t.tap(find.text('Mengerti'));
        await t.pumpAndSettle();

        // Coba lagi, kali ini tidak ada yang memegang.
        await t.tap(find.text('Tutup shift'));
        await t.pump();
        pertanyaan.last.complete(const []);
        await tunggu(t);
        await t.pumpAndSettle();
        await t.tap(find.text('Tutup Shift'));
        await t.pump();
        pertanyaan.last.complete(const []);
        await tunggu(t);
        await t.pump();
        expect(SessionManager.instance.currentSession!.shiftId, isNull);
        expect(find.text('Shift ditutup'), findsOneWidget);
        await lepas(t);
      });
    });

    testWidgets('Profil kasir dengan izin: Produk & Laporan muncul', (t) async {
      layarHp(t);
      await masuk(
        izin: const ['open_close_shift', 'manage_products', 'view_report'],
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfilKasirPage(
              repo: repo,
              repoBill: OpenBillRepository(db),
            ),
          ),
        ),
      );
      await tunggu(t);
      expect(find.text('Shift belum dibuka'), findsOneWidget);
      expect(find.text('Buka shift'), findsOneWidget);
      expect(find.text('Produk'), findsOneWidget);
      expect(find.text('Laporan'), findsOneWidget);
      expect(find.text('Kategori'), findsNothing);
      await lepas(t);
    });
  });
}
