import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/data/supabase/jam_server.dart';
import 'package:kasir_app/data/sync/sync_otomatis.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu akun kasir = satu HP (keputusan owner 12 Nov 2026,
/// supabase/akun_satu_hp.sql). Gantinya aturan lama "keluar sesudah 15
/// menit tidak disentuh" dan "sesi habis sesudah 12 jam".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sm = SessionManager.instance;
  final perangkat = PerangkatRepository.instance;
  final otomatis = SyncOtomatis.instance;
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
    sm.laporLepasShiftUntukTest = () async {};
    sm.tungguSinkronUntukTest = () async {};
  });

  tearDown(() async {
    await sm.clearSession();
    sm.sesiDicabut.value = null;
    sm.akanDikeluarkan.value = null;
    sm.laporLepasShiftUntukTest = null;
    sm.tungguSinkronUntukTest = null;
    perangkat.putusanAkun.value = null;
    JamServer.instance.aturUlang();
    otomatis.resetUntukTest();
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

  group('sesi tidak berakhir sendiri', () {
    for (final id in ['kasir-1', 'owner-1']) {
      test('$id: dibuka lagi 20 jam sesudah login dan tidak disentuh — '
          'langsung masuk', () async {
        final lama = sesi(id: id);
        final kemarin = DateTime.now().subtract(const Duration(hours: 20));
        final tersimpan = AuthSession(
          userId: lama.userId,
          username: lama.username,
          role: lama.role,
          shiftId: lama.shiftId,
          permissions: lama.permissions,
          createdAt: kemarin,
          expiresAt: kemarin.add(const Duration(hours: 12)),
        );
        SharedPreferences.setMockInitialValues({
          'auth_session': json.encode(tersimpan.toJson()),
          'sentuhan_terakhir': kemarin.toIso8601String(),
          'kabar_terakhir': kemarin.toIso8601String(),
        });
        await sm.restoreSession();
        expect(sm.currentSession?.userId, id);
        expect(sm.sesiDicabut.value, isNull);
      });
    }
  });

  group('masuk: akun kasir yang dipegang HP lain ditolak', () {
    late AuthRepository repo;
    final dipanggil = <String>[];
    var jawaban = (boleh: true, nama: null as String?);

    setUp(() async {
      dipanggil.clear();
      jawaban = (boleh: true, nama: null);
      repo = AuthRepository(
        db,
        pegangAkun: (id, sejak) async {
          dipanggil.add(id);
          return jawaban;
        },
      );
      final salt = CryptoUtils.generateSalt();
      for (final (id, nama, role) in [
        ('k-2', 'sari', 'cashier'),
        ('o-2', 'bos', 'owner'),
      ]) {
        await db.into(db.users).insert(UsersCompanion.insert(
              id: Value(id),
              username: nama,
              pinHash: CryptoUtils.hashPin('135791', salt),
              salt: salt,
              role: role,
            ));
      }
    });

    test('dipegang HP Kasir 1: ditolak dengan nama HP-nya', () async {
      jawaban = (boleh: false, nama: 'HP Kasir 1');
      await expectLater(
        repo.login(username: 'sari', pin: '135791'),
        throwsA(isA<AkunDitolak>().having(
          (e) => e.message,
          'pesan',
          AuthRepository.pesanAkunDipegang('HP Kasir 1'),
        )),
      );
      expect(dipanggil, ['k-2']);
    });

    test('boleh (termasuk offline — pegangAkun menjawab boleh): masuk',
        () async {
      expect(await repo.login(username: 'sari', pin: '135791'), isNotNull);
    });

    test('owner tidak dikunci: server tidak ditanya', () async {
      jawaban = (boleh: false, nama: 'HP lain');
      expect(await repo.login(username: 'bos', pin: '135791'), isNotNull);
      expect(dipanggil, isEmpty);
    });
  });

  group('laporan ke server', () {
    test('jawaban server dibaca jadi putusan', () {
      expect(PerangkatRepository.bacaPutusan('kalah'), PutusanAkun.kalah);
      expect(PerangkatRepository.bacaPutusan('dilepas'), PutusanAkun.dilepas);
      expect(PerangkatRepository.bacaPutusan('aman'), isNull);
      expect(PerangkatRepository.bacaPutusan(null), isNull,
          reason: 'server lama menjawab void');
    });

    test('akun kasir dilaporkan dengan jam mulai menurut jam server; owner '
        'tidak', () async {
      await sm.setSession(sesi(id: 'owner-1', shiftId: null));
      expect(perangkat.akunUntukLaporan(), isNull);

      final s = sesi();
      await sm.setSession(s);
      JamServer.instance.selisih.value = const Duration(minutes: 10);
      final akun = perangkat.akunUntukLaporan()!;
      expect(akun.id, 'kasir-1');
      expect(akun.sejak, s.createdAt.subtract(const Duration(minutes: 10)),
          reason: 'jam HP 10 menit kecepatan dikoreksi');
    });
  });

  group('HP yang kalah / dilepas keluar dengan aman', () {
    test('keranjang berisi: kasir diberi tahu, BELUM dikeluarkan', () async {
      await sm.setSession(sesi());
      perangkat.putusanAkun.value = PutusanAkun.kalah;
      otomatis.sedangMenyusunPesanan = true;
      await otomatis.tanganiPutusanAkun(hitungTertunda: () async => 0);
      expect(sm.isLoggedIn, isTrue);
      expect(sm.akanDikeluarkan.value, contains('sesudah pesanan ini selesai'));

      otomatis.sedangMenyusunPesanan = false;
      await otomatis.tanganiPutusanAkun(hitungTertunda: () async => 0);
      expect(sm.isLoggedIn, isFalse);
      expect(sm.sesiDicabut.value, SessionManager.pesanKalah);
      expect(sm.akanDikeluarkan.value, isNull);
    });

    test('data belum terkirim: dikirim dulu; masih tertahan = tetap masuk, '
        'dicoba lagi nanti', () async {
      await sm.setSession(sesi());
      perangkat.putusanAkun.value = PutusanAkun.kalah;
      var kirim = 0;
      await otomatis.tanganiPutusanAkun(
        hitungTertunda: () async => 2,
        kirim: () async => kirim++,
      );
      expect(kirim, 1);
      expect(sm.isLoggedIn, isTrue);

      var sisa = 2;
      await otomatis.tanganiPutusanAkun(
        hitungTertunda: () async => sisa,
        kirim: () async => sisa = 0,
      );
      expect(sm.isLoggedIn, isFalse, reason: 'semua terkirim, baru keluar');
    });

    test('dilepas owner: pesannya menyebut owner', () async {
      await sm.setSession(sesi());
      perangkat.putusanAkun.value = PutusanAkun.dilepas;
      await otomatis.tanganiPutusanAkun(hitungTertunda: () async => 0);
      expect(sm.sesiDicabut.value, SessionManager.pesanDilepas);
    });

    test('server berubah pikiran selama mengirim (HP lain sudah keluar): '
        'tidak dikeluarkan', () async {
      await sm.setSession(sesi());
      perangkat.putusanAkun.value = PutusanAkun.kalah;
      await otomatis.tanganiPutusanAkun(
        hitungTertunda: () async => perangkat.putusanAkun.value == null ? 0 : 1,
        kirim: () async => perangkat.putusanAkun.value = null,
      );
      expect(sm.isLoggedIn, isTrue);
    });

    test('server diberi tahu "tanpa akun" SESUDAH sesinya dihapus, menunggu '
        'sinkron yang sedang jalan (review R2)', () async {
      final sinkron = Completer<void>();
      final lapor = <String?>[];
      sm.tungguSinkronUntukTest = () => sinkron.future;
      sm.laporLepasShiftUntukTest =
          () async => lapor.add(sm.currentSession?.userId);
      await sm.setSession(sesi());
      await sm.keluarkanKarenaAkun(SessionManager.pesanKalah);
      await pumpEventQueue();
      expect(lapor, isEmpty, reason: 'sinkronnya belum selesai');
      sinkron.complete();
      await pumpEventQueue();
      expect(lapor, [null]);
    });

    test('selama menunggu sudah ada yang masuk lagi: laporan "tanpa akun" '
        'dilewati (review C6)', () async {
      final sinkron = Completer<void>();
      final lapor = <String>[];
      sm.tungguSinkronUntukTest = () => sinkron.future;
      sm.laporLepasShiftUntukTest = () async => lapor.add('dilepas');
      await sm.setSession(sesi());
      await sm.keluarkanKarenaAkun(SessionManager.pesanKalah);
      await sm.setSession(sesi());
      sinkron.complete();
      await pumpEventQueue();
      expect(lapor, isEmpty);
    });

    testWidgets('halaman login mengumumkan alasannya', (t) async {
      sm.sesiDicabut.value = SessionManager.pesanKalah;
      await t.pumpWidget(MaterialApp(home: LoginPage(repo: AuthRepository(db))));
      await t.pump();
      expect(find.text(SessionManager.pesanKalah), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
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
    await pumpEventQueue();
    expect(urutan, [
      'tunggu sinkron, masih masuk: false',
      'lapor shift null',
    ]);
  });

  group('lapor aktif ke server selama sinkron ditahan (A9)', () {
    final jam10 = DateTime(2026, 10, 23, 10);
    Duration menit(int m) => Duration(minutes: m);
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

    test('belum 5 menit: tidak lapor', () {
      expect(
        perlu(sentuhan: jam10.add(menit(3)), lapor: jam10,
            sekarang: jam10.add(menit(4))),
        isFalse,
      );
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
}
