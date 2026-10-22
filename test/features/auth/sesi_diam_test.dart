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
      await sm.catatKabar(kabar);

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

    test('owner tidak pernah terkena', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      await sm.catatKabar(DateTime(2026, 1, 1));
      expect(await sm.akhiriKalauDiam(), isFalse);
      expect(sm.isLoggedIn, isTrue);
    });

    test('kasir yang belum membuka shift tidak terkena', () async {
      await sm.setSession(sesi(shiftId: null));
      await sm.catatKabar(DateTime(2026, 1, 1));
      expect(await sm.akhiriKalauDiam(), isFalse);
      expect(sm.isLoggedIn, isTrue);
    });

    test('membuka shift sesudah lama diam memulai hitungan dari nol',
        () async {
      await sm.setSession(sesi(shiftId: null));
      await sm.catatKabar(DateTime.now().subtract(menit(40)));
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
        prefs['kabar_terakhir'] =
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
      await sm.catatKabar(DateTime.now().subtract(menit(20)));
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
        sm.catatKabar(DateTime.now().subtract(menit(15)));
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
}
