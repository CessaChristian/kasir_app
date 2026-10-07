import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/permission_repository.dart';
import 'package:kasir_app/features/owner/models/ringkasan_kasir.dart';
import 'package:kasir_app/features/owner/pages/hak_akses_page.dart';
import 'package:kasir_app/features/owner/pages/kelola_kasir_page.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/features/owner/widgets/lembar_kasir.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kelola Kasir dan Hak Akses (desain).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('status shift di kartu', () {
    final sekarang = DateTime(2026, 10, 7, 15);
    String label({DateTime? mulai, DateTime? selesai}) => labelStatusShift(
      mulaiBerjalan: mulai,
      selesaiTerakhir: selesai,
      sekarang: sekarang,
    );

    test('sedang shift, mulai hari ini', () {
      expect(
        label(mulai: DateTime(2026, 10, 7, 13, 26)),
        'Shift aktif sejak 13:26',
      );
    });
    test('sedang shift, mulai kemarin', () {
      expect(
        label(mulai: DateTime(2026, 10, 6, 21)),
        'Shift aktif sejak 6 Okt, 21:00',
      );
    });
    test('shift sudah selesai', () {
      expect(
        label(selesai: DateTime(2026, 9, 22, 21, 4)),
        'Shift terakhir 22 Sep 2026, 21:04',
      );
    });
    test('belum pernah shift', () {
      expect(label(), 'Belum pernah shift');
    });
  });

  group('validasi lembar', () {
    test('PIN baru', () {
      expect(periksaPinBaru('', ''), (null, false));
      expect(periksaPinBaru('123', ''), ('PIN harus 6 digit angka', false));
      expect(periksaPinBaru('123456', ''), (null, false));
      expect(periksaPinBaru('123456', '123450'), ('PIN belum cocok', false));
      expect(periksaPinBaru('123456', '123456'), ('PIN cocok', true));
    });
    test('username', () {
      expect(periksaUsername('  '), 'Username wajib diisi');
      expect(periksaUsername('ab'), 'Username harus 3–30 karakter');
      expect(periksaUsername('sari'), isNull);
    });
  });

  group('basis data dan halaman', () {
    late AppDatabase db;
    late CashierRepository repo;
    late PermissionRepository repoIzin;
    var online = true;
    var namaServer = <String>{};

    Future<void> akun(
      String id,
      String nama,
      String role, {
      bool aktif = true,
    }) => db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(id),
            username: nama,
            pinHash: 'h',
            salt: 's',
            role: role,
            isActive: Value(aktif),
            createdAt: Value(DateTime(2026, 1, int.parse(id.substring(2)))),
          ),
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
      online = true;
      namaServer = {};
      repo = CashierRepository(
        db,
        namaDipakaiDiServer: (nama, _) async => namaServer.contains(nama),
        terhubung: () async => online,
      );
      repoIzin = PermissionRepository(db);
      await akun('o-0', 'owner', 'owner');
      await akun('k-1', 'sari', 'cashier');
      await akun('k-2', 'dimas', 'cashier', aktif: false);
      await akun('k-3', 'budi', 'cashier');
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s1'),
              userId: 'k-1',
              startAt: Value(DateTime(2026, 9, 22, 8)),
              endAt: Value(DateTime(2026, 9, 22, 21, 4)),
            ),
          );
      for (final kode in [
        'open_close_shift',
        'create_transaction',
        'view_history',
      ]) {
        await repoIzin.setUserPermission(
          userId: 'k-1',
          permissionCode: kode,
          enabled: true,
        );
      }
      await SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'o-0',
          username: 'owner',
          role: 'owner',
          shiftId: null,
          permissions: const [],
        ),
      );
    });

    tearDown(() async {
      await SessionManager.instance.clearSession();
      SessionManager.dbOverride = null;
      await db.close();
    });

    test('daftar: aktif dulu, izin dihitung dari izin yang ada', () async {
      final d = await repo.watchDaftarKasir().first;
      expect([for (final r in d) r.akun.username], ['budi', 'sari', 'dimas']);
      final sari = d.firstWhere((r) => r.akun.username == 'sari');
      expect((sari.izinAktif, sari.izinTotal), (3, 6));
      expect(sari.selesaiShiftTerakhir, DateTime(2026, 9, 22, 21, 4));
      expect(sari.mulaiShiftBerjalan, isNull);
    });

    test('tanpa internet: semua perubahan akun ditolak', () async {
      online = false;
      Future<void> ditolak(Future<void> f) => expectLater(
        f,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'pesan',
            pesanButuhInternet,
          ),
        ),
      );
      await ditolak(repo.createCashier(username: 'rina', pin: '727272'));
      await ditolak(repo.toggleCashierStatus('k-1', false));
      await ditolak(repo.resetCashierPin('k-1', '123456'));
      await ditolak(repo.gantiNamaKasir('k-1', 'sari.w'));
      final sari = await (db.select(
        db.users,
      )..where((u) => u.id.equals('k-1'))).getSingle();
      expect(sari.isActive, isTrue, reason: 'tidak ada yang berubah');
    });

    test('tambah akun: username yang sudah ada di SERVER ditolak', () async {
      namaServer = {'rina'};
      await expectLater(
        repo.createCashier(username: 'rina', pin: '727272'),
        throwsA(isA<StateError>()),
      );
      expect(
        await (db.select(
          db.users,
        )..where((u) => u.username.equals('rina'))).get(),
        isEmpty,
      );
      await repo.createCashier(username: 'tari', pin: '727272');
    });

    test('menonaktifkan ikut mengakhiri shift yang berjalan', () async {
      await db
          .into(db.shifts)
          .insert(
            ShiftsCompanion.insert(
              id: const Value('s-jalan'),
              userId: 'k-3',
              startAt: Value(DateTime(2026, 10, 7, 13, 26)),
            ),
          );
      await repo.toggleCashierStatus('k-3', true);
      var s = await (db.select(
        db.shifts,
      )..where((x) => x.id.equals('s-jalan'))).getSingle();
      expect(s.endAt, isNull, reason: 'mengaktifkan tidak menyentuh shift');

      await repo.toggleCashierStatus('k-3', false);
      s = await (db.select(
        db.shifts,
      )..where((x) => x.id.equals('s-jalan'))).getSingle();
      expect(s.endAt, isNotNull);
      expect(s.syncStatus, 'pending', reason: 'ikut terkirim ke server');
      final lama = await (db.select(
        db.shifts,
      )..where((x) => x.id.equals('s1'))).getSingle();
      expect(
        lama.endAt,
        DateTime(2026, 9, 22, 21, 4),
        reason: 'shift yang sudah selesai tidak diubah',
      );
    });

    test('kelompok izin sesuai desain (Kelola Kategori belum ada)', () async {
      final kelompok = kelompokIzinDari(await repoIzin.getAllPermissions());
      // Dibandingkan sebagai teks: List di dalam record tidak dibandingkan
      // isinya.
      expect(
        [
          for (final (j, isi) in kelompok)
            '$j: ${[for (final d in isi) d.label].join(', ')}',
        ],
        [
          'OPERASIONAL: Buka Shift, Buat Transaksi, Lihat Riwayat Lengkap',
          'LAPORAN: Lihat Laporan, Lihat Shift Semua Kasir',
          'MANAJEMEN: Kelola Produk',
        ],
      );
    });

    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> bukaKelola(WidgetTester t) async {
      layarHp(t);
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(
            home: KelolaKasirPage(repo: repo, repoIzin: repoIzin),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      // Koneksi diperiksa dulu, baru daftar kasir dimuat.
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
    }

    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(Duration.zero);
    }

    testWidgets('kartu: status shift dan ringkasan hak akses', (t) async {
      await bukaKelola(t);
      expect(find.text('sari'), findsOneWidget);
      expect(find.text('Shift terakhir 22 Sep 2026, 21:04'), findsOneWidget);
      expect(find.text('3 dari 6 hak akses aktif'), findsOneWidget);
      expect(find.text('Belum pernah shift'), findsNWidgets(2));
      expect(find.byTooltip('Tambah akun kasir'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('menonaktifkan ditanya dulu; Batal tidak mengubah apa pun', (
      t,
    ) async {
      await bukaKelola(t);
      await t.tap(find.bySemanticsLabel('Akun sari aktif'));
      await t.pumpAndSettle();
      expect(find.text('Nonaktifkan sari?'), findsOneWidget);
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      final sari = await t.runAsync(
        () =>
            (db.select(db.users)..where((u) => u.id.equals('k-1'))).getSingle(),
      );
      expect(sari!.isActive, isTrue);
      await lepas(t);
    });

    testWidgets('tanpa internet: layar "butuh internet", Coba lagi', (t) async {
      online = false;
      await bukaKelola(t);
      expect(find.text('Kelola Kasir butuh internet'), findsOneWidget);
      expect(find.text('sari'), findsNothing);

      online = true;
      await t.tap(find.text('Coba lagi'));
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      expect(find.text('sari'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('nonaktifkan kasir yang sedang shift: disebut ikut diakhiri', (
      t,
    ) async {
      await t.runAsync(
        () => db
            .into(db.shifts)
            .insert(
              ShiftsCompanion.insert(
                id: const Value('s-jalan'),
                userId: 'k-3',
                startAt: Value(
                  DateTime.now().subtract(const Duration(minutes: 5)),
                ),
              ),
            ),
      );
      await bukaKelola(t);
      await t.tap(find.bySemanticsLabel('Akun budi aktif'));
      await t.pumpAndSettle();
      expect(find.textContaining('ikut diakhiri'), findsOneWidget);
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      await lepas(t);
    });

    testWidgets('menu ⋮: Hapus Akun tampil tapi belum melakukan apa-apa', (
      t,
    ) async {
      await bukaKelola(t);
      await t.tap(find.byTooltip('Menu akun').first);
      await t.pumpAndSettle();
      expect(find.text('Ubah Username'), findsOneWidget);
      await t.tap(find.text('Hapus Akun'));
      await t.pumpAndSettle();
      expect(
        find.text('Hapus Akun'),
        findsOneWidget,
        reason: 'lembar tetap terbuka, tidak ada yang terjadi',
      );
      final jumlah = await t.runAsync(() => db.select(db.users).get());
      expect(jumlah, hasLength(4));
      await lepas(t);
    });

    testWidgets('tambah akun: PIN harus 6 digit dan cocok', (t) async {
      await bukaKelola(t);
      await t.tap(find.byTooltip('Tambah akun kasir'));
      await t.pumpAndSettle();
      expect(find.text('Tambah Akun Kasir'), findsOneWidget);
      expect(find.text('PIN (6 digit)'), findsOneWidget);

      final kolom = find.byType(TextField);
      await t.enterText(kolom.at(0), 'rina');
      await t.enterText(kolom.at(1), '1234567890');
      expect(
        (t.widget<TextField>(kolom.at(1))).controller!.text,
        '123456',
        reason: 'ketikan berhenti di 6 digit',
      );
      await t.enterText(kolom.at(2), '123450');
      await t.tap(find.text('Simpan Akun'));
      await t.pump();
      expect(find.text('PIN belum cocok'), findsOneWidget);
      await lepas(t);
    });

    Future<void> bukaHakAkses(WidgetTester t) async {
      layarHp(t);
      await t.runAsync(() async {
        final sari = await (db.select(
          db.users,
        )..where((u) => u.id.equals('k-1'))).getSingle();
        await t.pumpWidget(
          MaterialApp(
            home: HakAksesPage(akun: sari, repo: repoIzin),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await t.pump();
    }

    testWidgets(
      'hak akses: Aktifkan semua ↔ Nonaktifkan semua, belum tersimpan',
      (t) async {
        await bukaHakAkses(t);
        await t.pump();
        expect(find.text('3 dari 6 akses aktif'), findsOneWidget);
        expect(find.text('OPERASIONAL'), findsOneWidget);

        await t.tap(find.text('Aktifkan semua'));
        await t.pump();
        expect(find.text('6 dari 6 akses aktif'), findsOneWidget);
        expect(find.text('Nonaktifkan semua'), findsOneWidget);

        final tersimpan = await t.runAsync(
          () => repoIzin.getUserPermissions('k-1'),
        );
        expect(
          tersimpan!.values.where((v) => v),
          hasLength(3),
          reason: 'belum disimpan',
        );
      },
    );

    testWidgets('hak akses: kembali dengan perubahan → "Buang perubahan?"', (
      t,
    ) async {
      layarHp(t);
      // Dibuka sebagai halaman kedua (seperti dari Kelola Kasir), supaya ada
      // tempat untuk kembali.
      await t.runAsync(() async {
        final sari = await (db.select(
          db.users,
        )..where((u) => u.id.equals('k-1'))).getSingle();
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HakAksesPage(akun: sari, repo: repoIzin),
                  ),
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        );
      });
      await t.tap(find.text('buka'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();

      // Tanpa perubahan: langsung kembali.
      await t.tap(find.byTooltip('Kembali'));
      await t.pumpAndSettle();
      expect(find.byType(HakAksesPage), findsNothing);

      await t.tap(find.text('buka'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Lihat Laporan'));
      await t.pump();
      await t.tap(find.byTooltip('Kembali'));
      await t.pumpAndSettle();
      expect(find.text('Buang perubahan?'), findsOneWidget);
      await t.tap(find.text('Buang'));
      await t.pumpAndSettle();
      expect(find.byType(HakAksesPage), findsNothing);
    });
  });
}
