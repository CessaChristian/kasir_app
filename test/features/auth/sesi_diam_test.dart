import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_otomatis.dart';
import 'package:kasir_app/data/sync/sync_service.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kasir yang memegang shift dan 15 menit tidak memberi kabar ke server harus
/// login ulang (keputusan owner 2026-10-20).
///
/// Server berhenti menghitung perangkat semacam itu sebagai pemegang shift
/// (supabase/shift_pemegang_basi.sql) — supaya HP yang mati tidak menahan
/// "Tutup shift" selamanya. HP-nya sendiri harus sepakat; kalau tidak, ia
/// terus berjualan di shift yang menurut server sudah tidak dipegangnya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sm = SessionManager.instance;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    for (final (id, role) in [('kasir-1', 'cashier'), ('owner-1', 'owner')]) {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: id,
            pinHash: 'h',
            salt: 's',
            role: role,
          ));
    }
  });

  tearDown(() async {
    await sm.clearSession();
    sm.sesiDicabut.value = null;
    SyncOtomatis.instance.resetUntukTest();
    SessionManager.dbOverride = null;
    await db.close();
  });

  AuthSession sesi({String id = 'kasir-1', String? shiftId = 'shift-1'}) =>
      AuthSession.create(
        userId: id,
        username: id,
        role: id == 'owner-1' ? 'owner' : 'cashier',
        shiftId: shiftId,
        permissions: const [],
      );

  Duration menit(int m) => Duration(minutes: m);

  group('batas 15 menit', () {
    test('angkanya 15 menit — sama dengan interval di SQL', () {
      expect(SessionManager.batasDiam, menit(15));
    });

    test('14:59 masih masuk, 15:00 login ulang dengan pesan', () async {
      await sm.setSession(sesi());
      final kabar = DateTime(2026, 10, 20, 9);
      sm.catatSentuhan(kabar);
      await pumpEventQueue();

      expect(
        await sm.akhiriKalauDiam(
            sekarang: kabar.add(menit(15) - const Duration(seconds: 1))),
        isFalse,
      );
      expect(sm.isLoggedIn, isTrue);

      expect(await sm.akhiriKalauDiam(sekarang: kabar.add(menit(15))), isTrue);
      expect(sm.isLoggedIn, isFalse);
      expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
    });

    test('owner tidak terkena aturan kabar kasir (owner diukur dari sentuhan '
        '— lihat grup B7e)', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      await sm.catatKabar(DateTime(2026, 1, 1));
      expect(await sm.akhiriKalauDiam(), isFalse);
      expect(sm.isLoggedIn, isTrue);
    });

    test('kasir yang belum membuka shift tidak terkena', () async {
      await sm.setSession(sesi(shiftId: null));
      sm.catatSentuhan(DateTime(2026, 1, 1));
      await pumpEventQueue();
      expect(await sm.akhiriKalauDiam(), isFalse);
      expect(sm.isLoggedIn, isTrue);
    });

    test('membuka shift sesudah lama diam memulai hitungan dari nol',
        () async {
      await sm.setSession(sesi(shiftId: null));
      sm.catatSentuhan(DateTime.now().subtract(menit(40)));
      await pumpEventQueue();
      await sm.aturShift('shift-1');
      expect(await sm.akhiriKalauDiam(), isFalse,
          reason: 'kasir baru saja menekan Buka shift — jelas sedang dipakai');
    });
  });

  group('aplikasi dibuka lagi (misalnya sesudah digeser dari riwayat)', () {
    Future<void> simpanSesi({Duration? diam}) async {
      final prefs = <String, Object>{
        'auth_session': json.encode(sesi().toJson()),
      };
      if (diam != null) {
        prefs['sentuhan_terakhir'] =
            DateTime.now().subtract(diam).toIso8601String();
      }
      await sm.clearSession();
      SharedPreferences.setMockInitialValues(prefs);
    }

    test('diam 20 menit: harus login, pesannya menunggu di halaman login',
        () async {
      await simpanSesi(diam: menit(20));
      await sm.restoreSession();
      expect(sm.isLoggedIn, isFalse);
      expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
    });

    test('diam 5 menit: langsung masuk', () async {
      await simpanSesi(diam: menit(5));
      await sm.restoreSession();
      expect(sm.isLoggedIn, isTrue);
      expect(sm.sesiDicabut.value, isNull);
    });

    test('belum pernah tercatat (baru pasang APK ini): tidak dikeluarkan',
        () async {
      await simpanSesi();
      await sm.restoreSession();
      expect(sm.isLoggedIn, isTrue);
    });

    testWidgets('halaman login mengumumkan alasannya', (t) async {
      sm.sesiDicabut.value = SessionManager.pesanDiam;
      await t.pumpWidget(MaterialApp(home: LoginPage(repo: AuthRepository(db))));
      await t.pump();
      expect(find.text(SessionManager.pesanDiam), findsOneWidget);
      expect(sm.sesiDicabut.value, isNull, reason: 'cukup diumumkan sekali');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });
  });

  test('internet mati TIDAK dihitung diam: putaran sinkron yang gagal pun '
      'mencatat kabar', () async {
    await sm.setSession(sesi());
    await sm.catatKabar(DateTime.now().subtract(menit(40)));

    // Di test tidak ada server sama sekali — putarannya gagal tersambung.
    final hasil = await SyncService.instance.jalankan();
    expect(hasil.berhasil, isFalse);

    expect(await sm.akhiriKalauDiam(), isFalse);
    expect(sm.isLoggedIn, isTrue);
  });

  group('sinkron otomatis', () {
    test('kembali dari latar belakang: diperiksa SEBELUM sinkron', () async {
      await sm.setSession(sesi());
      sm.catatSentuhan(DateTime.now().subtract(menit(20)));
      await pumpEventQueue();
      bool? masukSaatSinkron;
      SyncOtomatis.instance.penggantiPicuUntukTest =
          (_) async => masukSaatSinkron = sm.isLoggedIn;

      await SyncOtomatis.instance.kembaliAktif();

      expect(masukSaatSinkron, isFalse,
          reason: 'sinkron mencatat kabar baru — kalau ia jalan duluan, HP '
              'yang diam 20 menit terlihat baru saja aktif');
      expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
    });

    test('keranjang dibiarkan berisi: berakhir dalam semenit, tanpa menunggu '
        'sinkron berkala', () {
      fakeAsync((async) {
        sm.setSession(sesi());
        async.flushMicrotasks();
        SyncOtomatis.instance.penggantiPicuUntukTest = (_) async {};
        SyncOtomatis.instance.kembaliAktif();
        async.flushMicrotasks();
        expect(sm.isLoggedIn, isTrue);

        // Keranjang berisi = sinkron dilewati = tidak ada kabar baru.
        SyncOtomatis.instance.sedangMenyusunPesanan = true;
        sm.catatSentuhan(DateTime.now().subtract(menit(15)));
        async.flushMicrotasks();

        async.elapse(SyncOtomatis.jarakPeriksaDiam);
        expect(sm.isLoggedIn, isFalse);
        expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
      });
    });
  });

  test('Keluar: sesi dihapus, sinkron yang berjalan ditunggu, BARU tanda '
      'shift dilepas', () async {
    await sm.setSession(sesi());
    final urutan = <String>[];
    await AuthRepository(
      db,
      tungguSinkron: () async =>
          urutan.add('tunggu sinkron, masih masuk: ${sm.isLoggedIn}'),
      lapor: (shiftId) async => urutan.add('lapor shift $shiftId'),
    ).logout();

    expect(urutan, [
      'tunggu sinkron, masih masuk: false',
      'lapor shift null',
    ], reason: 'sinkron yang selesai belakangan membawa shift dari sesi — '
        'sesinya harus sudah kosong, dan laporan "tanpa shift" yang terakhir');
  });

  group('sentuhan dihitung aktif (A9)', () {
    // Terbukti di HP: keranjang berisi, kasir masih melayani, 12 menit
    // kemudian dikeluarkan paksa dan pesanannya hilang — karena kabar hanya
    // dicatat sinkron, dan sinkron ditahan selama keranjang berisi.

    test('kasir yang terus menyentuh layar tidak dikeluarkan', () async {
      await sm.setSession(sesi());
      final sinkronTerakhir = DateTime(2026, 10, 23, 10);
      await sm.catatKabar(sinkronTerakhir);
      sm.catatSentuhan(sinkronTerakhir.add(menit(14)));
      await pumpEventQueue();

      expect(await sm.akhiriKalauDiam(
              sekarang: sinkronTerakhir.add(menit(20))),
          isFalse);
      expect(sm.isLoggedIn, isTrue);
    });

    test('HP yang ditinggal tetap dikeluarkan 15 menit sesudah sentuhan '
        'terakhir', () async {
      await sm.setSession(sesi());
      final sentuh = DateTime(2026, 10, 23, 10);
      await sm.catatKabar(sentuh.subtract(menit(30)));
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();

      expect(await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(15))),
          isTrue);
      expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
    });

    test('sentuhan beruntun tidak menulis penyimpanan tiap kali', () async {
      await sm.setSession(sesi());
      final awal = DateTime(2026, 10, 23, 10);
      await sm.catatKabar(awal);
      Future<String?> tersimpan() async =>
          (await SharedPreferences.getInstance()).getString('kabar_terakhir');

      sm.catatSentuhan(awal.add(const Duration(seconds: 30)));
      await pumpEventQueue();
      expect(await tersimpan(), awal.toIso8601String(),
          reason: 'belum semenit: cukup di memori');
      expect(sm.sentuhanTerakhir, awal.add(const Duration(seconds: 30)));

      final semenit = awal.add(const Duration(minutes: 1, seconds: 1));
      sm.catatSentuhan(semenit);
      await pumpEventQueue();
      expect(await tersimpan(), semenit.toIso8601String());
    });
  });

  group('lapor aktif ke server selama sinkron ditahan (A9)', () {
    final jam10 = DateTime(2026, 10, 23, 10);
    bool perlu({
      bool ditahan = true,
      DateTime? sentuhan,
      DateTime? lapor,
      required DateTime sekarang,
    }) =>
        SyncOtomatis.perluLaporAktif(
          sinkronDitahan: ditahan,
          sentuhan: sentuhan,
          laporTerakhir: lapor,
          sekarang: sekarang,
        );

    test('keranjang berisi + disentuh + laporan terakhir ≥ 5 menit: lapor', () {
      expect(
        perlu(sentuhan: jam10.add(menit(4)), lapor: jam10,
            sekarang: jam10.add(menit(5))),
        isTrue,
      );
    });

    test('belum 5 menit: tidak lapor (paling sering sekali per 5 menit)', () {
      expect(
        perlu(sentuhan: jam10.add(menit(3)), lapor: jam10,
            sekarang: jam10.add(menit(4))),
        isFalse,
      );
      expect(SyncOtomatis.jarakBerkala, menit(5));
    });

    test('tidak disentuh sejak laporan terakhir: tidak lapor — HP yang '
        'ditinggal harus terlihat diam di server', () {
      expect(
        perlu(sentuhan: jam10.subtract(menit(1)), lapor: jam10,
            sekarang: jam10.add(menit(20))),
        isFalse,
      );
      expect(perlu(sentuhan: null, lapor: jam10, sekarang: jam10.add(menit(9))),
          isFalse);
    });

    test('sinkron tidak ditahan: sinkron berkala sudah melapor sendiri', () {
      expect(
        perlu(ditahan: false, sentuhan: jam10.add(menit(9)), lapor: jam10,
            sekarang: jam10.add(menit(10))),
        isFalse,
      );
    });

    test('belum pernah lapor sejak aplikasi dibuka: lapor', () {
      expect(perlu(sentuhan: jam10, lapor: null, sekarang: jam10), isTrue);
    });
  });

  group('owner: hanya sentuhan yang dihitung (B7e)', () {
    test('owner yang ditinggal 15 menit tanpa disentuh dikeluarkan', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      final sentuh = DateTime(2026, 10, 24, 9);
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();

      expect(await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(14))),
          isFalse);
      expect(await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(15))),
          isTrue);
      expect(sm.sesiDicabut.value, SessionManager.pesanDiamOwner);
    });

    test('sinkron TIDAK menyelamatkan owner yang ditinggal', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      final sentuh = DateTime(2026, 10, 24, 9);
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();
      // Sinkron berkala terus mencatat kabar selama aplikasi terbuka.
      await sm.catatKabar(sentuh.add(menit(19)));
      expect(await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(20))),
          isTrue);
    });

    test('baru login: tidak langsung dikeluarkan', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      expect(await sm.akhiriKalauDiam(), isFalse);
    });

    test('ditinggal lalu aplikasinya dibuka ulang: tetap ketahuan', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      final sentuh = DateTime.now().subtract(menit(40));
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();
      // Aplikasi dibuka ulang: langsung dikeluarkan saat sesinya dipulihkan.
      await sm.restoreSession();
      expect(sm.isLoggedIn, isFalse,
          reason: 'jam sentuhan terakhir tersimpan, bukan hanya di memori');
      expect(sm.sesiDicabut.value, SessionManager.pesanDiamOwner);
    });

  });

  group('QA S4: kasir pemegang shift juga diukur dari sentuhan', () {
    // Dulu sinkron tiap 5 menit ikut dihitung "masih dipakai": HP kasir yang
    // ditinggal dengan aplikasi terbuka tidak pernah keluar, dan HP lain
    // tidak bisa menutup shift-nya (keputusan owner 2026-10-30).
    test('sinkron TIDAK menyelamatkan kasir yang ditinggal', () async {
      await sm.setSession(sesi());
      final sentuh = DateTime(2026, 10, 30, 9);
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();
      await sm.catatKabar(sentuh.add(menit(14)));
      expect(await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(15))),
          isTrue);
      expect(sm.sesiDicabut.value, SessionManager.pesanDiam);
    });

    test('keluar karena diam: server langsung diberi tahu shift dilepas',
        () async {
      final lapor = <String?>[];
      sm.laporLepasShiftUntukTest = () async => lapor.add(sm.currentSession?.shiftId);
      addTearDown(() => sm.laporLepasShiftUntukTest = null);
      await sm.setSession(sesi());
      final sentuh = DateTime(2026, 10, 30, 9);
      sm.catatSentuhan(sentuh);
      await pumpEventQueue();
      await sm.akhiriKalauDiam(sekarang: sentuh.add(menit(15)));
      expect(lapor, [null], reason: 'dilaporkan SESUDAH sesinya dihapus');
    });
  });
}
