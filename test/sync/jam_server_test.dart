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

  group('penukaran tiket saat jam salah (audit 6 Nov nomor 8)', () {
    final uriTukar = Uri.parse(
        'https://contoh.test/auth/v1/token?grant_type=refresh_token');
    late int kirim;
    late int status;
    late int umurDetik;
    late KlienBerbatasWaktu klien;

    /// Tiket akses palsu dengan `exp` dari jam SERVER.
    String tiketAkses(int umur) {
      final jamServer = DateTime.now().subtract(jam.selisih.value!);
      final exp = jamServer.add(Duration(seconds: umur)).millisecondsSinceEpoch ~/
          1000;
      String b64(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return '${b64({'alg': 'HS256'})}.${b64({'exp': exp})}.ttd';
    }

    // Server sungguhan memberi tiket pengganti BARU di setiap tukar.
    setUp(() {
      kirim = 0;
      status = 200;
      umurDetik = 3600;
      klien = KlienBerbatasWaktu(MockClient((r) async {
        kirim++;
        if (status != 200) return http.Response('{"msg":"x"}', status);
        final lama = (jsonDecode(r.body) as Map)['refresh_token'] as String;
        return http.Response(
          jsonEncode({
            'access_token': tiketAkses(umurDetik),
            'refresh_token': '$lama+',
            'token_type': 'bearer',
          }),
          200,
        );
      }));
    });

    Future<String> tukar(String tiket) async {
      final r = await klien.post(uriTukar,
          body: jsonEncode({'refresh_token': tiket}));
      return r.statusCode == 200
          ? (jsonDecode(r.body) as Map)['refresh_token'] as String
          : 'gagal ${r.statusCode}';
    }

    test('jam salah: SDK menukar tiket pengganti berulang, server cukup sekali',
        () async {
      jam.selisih.value = const Duration(days: 1);
      final r2 = await tukar('r1');
      expect(r2, 'r1+');
      // SDK lalu memakai tiket pengganti itu, berulang-ulang.
      expect(await tukar(r2), 'r1+');
      expect(await tukar(r2), 'r1+');
      expect(await tukar('r1'), 'r1+');
      expect(kirim, 1);
    });

    test('tiket hampir habis menurut jam server: ditukar sungguhan', () async {
      jam.selisih.value = const Duration(days: 1);
      umurDetik = 30;
      final r2 = await tukar('r1');
      await tukar(r2);
      expect(kirim, 2);
    });

    test('jam benar: setiap tukar sampai ke server', () async {
      jam.selisih.value = Duration.zero;
      final r2 = await tukar('r1');
      await tukar(r2);
      expect(kirim, 2);
    });

    test('jam dibenerin: jawaban simpanan tidak dipakai lagi', () async {
      jam.selisih.value = const Duration(days: 1);
      final r2 = await tukar('r1');
      jam.selisih.value = Duration.zero;
      expect(await tukar(r2), 'r1++');
      expect(kirim, 2);
    });

    test('jawaban gagal tidak disimpan, tiket lain ditukar sungguhan', () async {
      jam.selisih.value = const Duration(days: 1);
      status = 400;
      await tukar('r1');
      await tukar('r1');
      expect(kirim, 2);
      status = 200;
      await tukar('r1');
      await tukar('lain');
      expect(kirim, 4);
    });

    test('permintaan selain penukaran tidak disimpan', () async {
      jam.selisih.value = const Duration(days: 1);
      final lain = Uri.parse('https://contoh.test/rest/v1/products');
      final k = KlienBerbatasWaktu(MockClient((_) async {
        kirim++;
        return http.Response('[]', 200);
      }));
      await k.post(lain, body: 'a');
      await k.post(lain, body: 'a');
      expect(kirim, 2);
    });
  });

  group('sesudah 429, penukaran ditahan (audit 6 Nov nomor 9)', () {
    final uriTukar = Uri.parse(
        'https://contoh.test/auth/v1/token?grant_type=refresh_token');

    test('penolakan berikutnya tidak dikirim ke server selama ditahan',
        () async {
      var kirim = 0;
      final klien = KlienBerbatasWaktu(MockClient((_) async {
        kirim++;
        return http.Response('batas', 429);
      }));
      for (var i = 0; i < 6; i++) {
        final r = await klien.post(uriTukar, body: '{"refresh_token":"r1"}');
        expect(r.statusCode, greaterThanOrEqualTo(500));
      }
      expect(kirim, 1);
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
    var kirimKeServer = 0;
    /// SDK sungguhan, lewat klien aplikasi, dengan server yang menjawab [kode].
    /// Yang diuji perilaku SDK-nya: tiket dihapus atau disimpan.
    Future<GoTrueClient> tukarDenganJawaban(int kode, String isi) async {
      final auth = GoTrueClient(
        url: 'https://contoh.test/auth/v1',
        httpClient: KlienBerbatasWaktu(
          MockClient((_) async {
            kirimKeServer++;
            return http.Response(isi, kode);
          }),
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
      kirimKeServer = 0;
      final auth = await tukarDenganJawaban(
        429,
        '{"code":429,"error_code":"over_request_rate_limit",'
            '"msg":"Request rate limit reached"}',
      );
      expect(auth.currentSession, isNotNull);
      expect(kirimKeServer, 1,
          reason: 'SDK mengulang 5xx, tapi ulangannya tidak boleh sampai server');
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
