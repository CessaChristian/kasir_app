import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/recovery/pages/owner_recovery_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/features/dashboard/widgets/kisi_produk_laris.dart';
import 'package:kasir_app/features/shift/models/produk_laris.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/kerangka_masuk.dart';
import 'package:kasir_app/shared/ui/skala_layar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tampilan di HP sungguhan (2026-10-17): Realme RMX3085 (1080×2400,
/// density 480 → 360×800 dp) menampilkan semuanya ±14% lebih besar daripada
/// emulator Pixel 8a (density 420 → 411×914 dp), Login dan Dashboard harus
/// digulir. Layar sempit kini digambar seperti layar acuan (SkalaLayar), dan
/// Login/Dashboard menyesuaikan tinggi layar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// (nama, piksel, density/160)
  const hpRealme = ('HP 360×800 dp', Size(1080, 2400), 3.0);
  const emulator = ('emulator 411×914 dp', Size(1080, 2400), 2.625);
  const hpPendek = ('HP pendek 16:9 360×640 dp', Size(1080, 1920), 3.0);

  void layar(
    WidgetTester t,
    (String, Size, double) l, {
    bool statusBar = true,
  }) {
    t.view.physicalSize = l.$2;
    t.view.devicePixelRatio = l.$3;
    // Status bar 110 piksel — tinggi asli di Realme RMX3085 (kamera
    // berlubang membuatnya lebih tinggi daripada 24 dp biasa).
    if (statusBar) t.view.padding = const FakeViewPadding(top: 110);
    addTearDown(t.view.reset);
  }

  Widget aplikasi(Widget halaman) => MaterialApp(
    builder: (context, child) => SkalaLayar(child: child!),
    home: halaman,
  );

  group('skalaUntukLebar', () {
    test('layar acuan atau lebih lebar: tidak diubah', () {
      expect(skalaUntukLebar(411), 1);
      expect(skalaUntukLebar(600), 1);
    });
    test('360 dp dikecilkan pas ke lebar acuan', () {
      expect(skalaUntukLebar(360), closeTo(360 / 411, 1e-9));
    });
    test('layar sangat sempit: paling kecil 0,85', () {
      expect(skalaUntukLebar(300), skalaMin);
    });
  });

  group('SkalaLayar', () {
    testWidgets('layar 360 dp: halaman melihat lebar acuan, ketukan tepat', (
      t,
    ) async {
      layar(t, hpRealme);
      Size? terlihat;
      EdgeInsets? aman;
      var diketuk = 0;
      await t.pumpWidget(
        aplikasi(
          Builder(
            builder: (c) {
              terlihat = MediaQuery.sizeOf(c);
              aman = MediaQuery.paddingOf(c);
              return Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  onPressed: () => diketuk++,
                  child: const Text('ketuk'),
                ),
              );
            },
          ),
        ),
      );
      expect(terlihat!.width, closeTo(lebarAcuan, 1e-6));
      expect(terlihat!.height, closeTo(800 * lebarAcuan / 360, 1e-6));
      expect(aman!.top, closeTo(110 / 3 * lebarAcuan / 360, 1e-6));
      // Tombol di pojok kanan bawah tetap di dalam layar sungguhan dan
      // ketukan di sana sampai ke tombolnya.
      final kotak = t.getRect(find.text('ketuk'));
      expect(kotak.right, lessThanOrEqualTo(360));
      expect(kotak.bottom, lessThanOrEqualTo(800));
      await t.tap(find.text('ketuk'));
      expect(diketuk, 1);
    });

    testWidgets('layar acuan: tidak dibungkus apa pun', (t) async {
      layar(t, emulator);
      await t.pumpWidget(aplikasi(const Text('x')));
      expect(
        find.descendant(
          of: find.byType(SkalaLayar),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
    });
  });

  group('Login muat tanpa digulir', () {
    late AppDatabase db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
    });
    tearDown(() async {
      SessionManager.dbOverride = null;
      await db.close();
    });

    /// Rect tombol Masuk dalam PIKSEL layar, dan panjang gulir yang tersisa.
    Future<(Rect, double)> bukaLogin(
      WidgetTester t,
      (String, Size, double) l, {
      bool statusBar = true,
    }) async {
      layar(t, l, statusBar: statusBar);
      await t.pumpWidget(aplikasi(LoginPage(repo: AuthRepository(db))));
      await t.pump();
      final masuk = t.getRect(find.text('Masuk'));
      final gulir = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      final d = l.$3;
      return (
        Rect.fromLTRB(
          masuk.left * d,
          masuk.top * d,
          masuk.right * d,
          masuk.bottom * d,
        ),
        gulir,
      );
    }

    for (final l in [hpRealme, emulator, hpPendek]) {
      testWidgets(l.$1, (t) async {
        final (masuk, gulir) = await bukaLogin(t, l);
        expect(gulir, 0, reason: 'tidak ada yang perlu digulir');
        expect(masuk.bottom, lessThanOrEqualTo(l.$2.height));
      });
    }

    /// Panjang gulir Reset PIN (3 kolom) dan bawah tombolnya dalam piksel.
    Future<(double, double)> bukaReset(
      WidgetTester t,
      (String, Size, double) l,
    ) async {
      layar(t, l);
      await t.pumpWidget(aplikasi(OwnerRecoveryPage(repo: AuthRepository(db))));
      await t.pump();
      final tombol = t.getRect(find.widgetWithText(TombolMasuk, 'Reset PIN'));
      final gulir = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      return (gulir, tombol.bottom * l.$3);
    }

    for (final l in [hpRealme, emulator, hpPendek]) {
      testWidgets('Reset PIN, ${l.$1}', (t) async {
        final (gulir, bawah) = await bukaReset(t, l);
        expect(gulir, 0, reason: 'tidak ada yang perlu digulir');
        expect(bawah, lessThanOrEqualTo(l.$2.height));
      });
    }

    testWidgets('keyboard muncul: logo menciut, tombol Masuk di atasnya', (
      t,
    ) async {
      layar(t, hpRealme);
      await t.pumpWidget(aplikasi(LoginPage(repo: AuthRepository(db))));
      await t.pump();
      final logoAwal = t.getSize(find.bySemanticsLabel('Teras Inn').first);
      // Keyboard angka di HP user: ±816 piksel (diukur dari tangkapan layar).
      t.view.viewInsets = const FakeViewPadding(bottom: 816);
      await t.pump();
      final logo = t.getSize(find.bySemanticsLabel('Teras Inn').first);
      expect(logo.height, lessThan(logoAwal.height));
      final masuk = t.getRect(find.text('Masuk'));
      expect(masuk.bottom * 3, lessThanOrEqualTo(2400 - 816));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('layar tinggi: logo paling tinggi 320, panel sampai bawah', (
      t,
    ) async {
      const tinggi = ('layar tinggi', Size(1080, 3200), 2.625);
      layar(t, tinggi);
      await t.pumpWidget(aplikasi(LoginPage(repo: AuthRepository(db))));
      await t.pump();
      final panel = t.getRect(
        find
            .ancestor(
              of: find.text('Login to Access Your'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        panel.top,
        closeTo(110 / 2.625 + 320, 0.5),
        reason: 'status bar + logo',
      );
      expect(panel.bottom, closeTo(3200 / 2.625, 0.5));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('HP 360 dp tampil sama dengan emulator', (t) async {
      // Tanpa status bar: tingginya berbeda per HP (24 dp = 72 piksel di
      // density 480, 63 piksel di 420) dan bukan urusan aplikasi.
      final (hp, _) = await bukaLogin(t, hpRealme, statusBar: false);
      final (emu, _) = await bukaLogin(t, emulator, statusBar: false);
      // Dua-duanya 1080×2400 piksel: tombol Masuk di piksel yang sama.
      // Toleransi 4 piksel: sesudah diskalakan layar HP setinggi ±913 dp,
      // emulator 914 dp — area logo memakai sisa tinggi itu.
      expect(hp.top, closeTo(emu.top, 4));
      expect(hp.height, closeTo(emu.height, 2));
    });
  });

  group('foto Produk Paling Laris', () {
    test('120 di layar acuan, menyusut di layar pendek, minimal 80', () {
      expect(KisiProdukLaris.tinggiFoto(914), closeTo(120, 0.5));
      expect(KisiProdukLaris.tinggiFoto(1200), 120);
      expect(KisiProdukLaris.tinggiFoto(730), closeTo(96, 0.5));
      expect(KisiProdukLaris.tinggiFoto(500), 80);
    });

    testWidgets('mengikuti tinggi layar', (t) async {
      Future<double> tinggiKartu((String, Size, double) l) async {
        layar(t, l);
        await t.pumpWidget(
          aplikasi(
            Scaffold(
              body: ListView(
                children: [
                  KisiProdukLaris(
                    daftar: [
                      for (var i = 0; i < 4; i++)
                        ProdukLaris(idProduk: 'p$i', nama: 'P$i', terjual: 1),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        return t.getSize(find.byType(Material).last).height;
      }

      final acuan = await tinggiKartu(emulator);
      final pendek = await tinggiKartu(hpPendek);
      expect(pendek, lessThan(acuan));
    });
  });
}
