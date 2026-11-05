import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_app/data/supabase/jam_server.dart';
import 'package:kasir_app/data/supabase/klien_berbatas_waktu.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, GoTrueClient, Session, User;

void main() {
  final jam = JamServer.instance;
  const header = 'Thu, 05 Nov 2026 10:00:00 GMT';
  final server = DateTime.utc(2026, 11, 5, 10);
  tearDown(jam.aturUlang);

  group('selisih jam', () {
    test('belum ada jawaban server: tidak dianggap salah', () {
      expect(jam.selisih.value, isNull);
      expect(jam.jamSalah, isFalse);
    });

    test('jam HP maju sehari dan mundur sehari terbaca arahnya', () {
      jam.catat(header, jamHp: server.add(const Duration(days: 1)));
      expect(jam.selisih.value, const Duration(days: 1));
      expect(jam.jamSalah, isTrue);
      jam.catat(header, jamHp: server.subtract(const Duration(days: 1)));
      expect(jam.selisih.value, const Duration(days: -1));
      expect(jam.jamSalah, isTrue);
    });

    test('di bawah 5 menit masih wajar, 5 menit sudah salah', () {
      jam.catat(header, jamHp: server.add(const Duration(minutes: 4)));
      expect(jam.jamSalah, isFalse);
      jam.catat(header, jamHp: server.add(const Duration(minutes: 5)));
      expect(jam.jamSalah, isTrue);
    });

    test('jam dibenerin: peringatannya hilang', () {
      jam.catat(header, jamHp: server.add(const Duration(days: 1)));
      jam.catat(header, jamHp: server);
      expect(jam.jamSalah, isFalse);
    });

    test('header rusak atau tidak ada diabaikan', () {
      jam.catat(null);
      jam.catat('bukan tanggal');
      expect(jam.selisih.value, isNull);
    });

    test('tiap jawaban lewat klien aplikasi ikut dicatat', () async {
      final klien = KlienBerbatasWaktu(
        MockClient((_) async => http.Response('', 200, headers: {'date': header})),
      );
      await klien.get(Uri.parse('https://contoh.test/'));
      expect(jam.selisih.value, isNotNull);
    });
  });

  group('penukaran tiket saat jam salah', () {
    final uriTukar = Uri.parse(
        'https://contoh.test/auth/v1/token?grant_type=refresh_token');
    Future<http.Response> tukar(http.Client k, [String isi = 'r1']) =>
        k.post(uriTukar, body: isi);
    late int kirim;
    late int status;
    late KlienBerbatasWaktu klien;
    setUp(() {
      kirim = 0;
      status = 200;
      klien = KlienBerbatasWaktu(MockClient((_) async {
        kirim++;
        return http.Response('tiket$kirim', status);
      }));
    });

    test('jam salah: tukar berulang hanya sekali sampai ke server', () async {
      jam.selisih.value = const Duration(days: 1);
      expect((await tukar(klien)).body, 'tiket1');
      expect((await tukar(klien)).body, 'tiket1');
      expect((await tukar(klien)).body, 'tiket1');
      expect(kirim, 1);
    });

    test('jam benar: setiap tukar tetap sampai ke server', () async {
      jam.selisih.value = Duration.zero;
      await tukar(klien);
      await tukar(klien);
      expect(kirim, 2);
    });

    test('jam dibenerin: jawaban simpanan tidak dipakai lagi', () async {
      jam.selisih.value = const Duration(days: 1);
      await tukar(klien);
      jam.selisih.value = Duration.zero;
      expect((await tukar(klien)).body, 'tiket2');
    });

    test('tiket berbeda dan jawaban gagal tidak memakai simpanan', () async {
      jam.selisih.value = const Duration(days: 1);
      status = 400;
      await tukar(klien);
      await tukar(klien);
      expect(kirim, 2, reason: 'jawaban gagal tidak boleh disimpan');
      status = 200;
      await tukar(klien);
      await tukar(klien, 'r2');
      expect(kirim, 4, reason: 'tiket lain harus benar-benar ditukar');
    });

    test('permintaan selain penukaran tidak disimpan', () async {
      jam.selisih.value = const Duration(days: 1);
      final lain = Uri.parse('https://contoh.test/rest/v1/products');
      await klien.post(lain, body: 'a');
      await klien.post(lain, body: 'a');
      expect(kirim, 2);
    });
  });

  group('tiket tidak hilang karena batas permintaan', () {
    final uriTukar = Uri.parse(
        'https://contoh.test/auth/v1/token?grant_type=refresh_token');

    test('429 saat menukar terbaca sebagai gangguan sementara (5xx)', () async {
      final klien = KlienBerbatasWaktu(
        MockClient((_) async => http.Response('batas', 429)),
      );
      final r = await klien.post(uriTukar, body: 'r1');
      expect(r.statusCode, greaterThanOrEqualTo(500),
          reason: 'SDK menghapus tiket untuk penolakan di bawah 500');
    });

    test('429 di permintaan lain dan 400 saat menukar tetap apa adanya',
        () async {
      var kode = 429;
      final klien = KlienBerbatasWaktu(
        MockClient((_) async => http.Response('x', kode)),
      );
      final data = await klien.get(Uri.parse('https://contoh.test/rest/v1/a'));
      expect(data.statusCode, 429);
      kode = 400;
      expect((await klien.post(uriTukar, body: 'r1')).statusCode, 400,
          reason: 'tiket yang benar-benar dicabut tetap harus ketahuan');
    });
  });

  group('SDK login asli saat tiket ditukar', () {
    /// SDK sungguhan, lewat klien aplikasi, dengan server yang menjawab [kode].
    /// Yang diuji perilaku SDK-nya: tiket dihapus atau disimpan.
    Future<GoTrueClient> tukarDenganJawaban(int kode, String isi) async {
      final auth = GoTrueClient(
        url: 'https://contoh.test/auth/v1',
        httpClient: KlienBerbatasWaktu(
          MockClient((_) async => http.Response(isi, kode)),
        ),
        autoRefreshToken: false,
      );
      final sesi = Session(
        accessToken: 'bukan.jwt.asli',
        refreshToken: 'r1',
        tokenType: 'bearer',
        user: const User(
          id: '00000000-0000-0000-0000-000000000001',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      await auth.setInitialSession(jsonEncode(sesi.toJson()));
      expect(auth.currentSession, isNotNull);
      await expectLater(auth.refreshSession(), throwsA(isA<AuthException>()));
      return auth;
    }

    test('429: tiket TETAP ada, jadi HP tidak perlu daftar ulang', () async {
      final auth = await tukarDenganJawaban(
        429,
        '{"code":429,"error_code":"over_request_rate_limit",'
            '"msg":"Request rate limit reached"}',
      );
      expect(auth.currentSession, isNotNull);
    });

    test('tiket benar-benar dicabut server: tetap dihapus', () async {
      final auth = await tukarDenganJawaban(
        400,
        '{"code":400,"error_code":"refresh_token_not_found",'
            '"msg":"Invalid Refresh Token"}',
      );
      expect(auth.currentSession, isNull);
    });
  });

  group('keterangan selisih', () {
    test('menyebut arah dan lamanya', () {
      expect(JamServer.keterangan(const Duration(days: 1, hours: 2)),
          'lebih cepat 1 hari');
      expect(JamServer.keterangan(const Duration(hours: -3)),
          'lebih lambat 3 jam');
      expect(JamServer.keterangan(const Duration(minutes: 7)),
          'lebih cepat 7 menit');
    });
  });
}
