import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'jam_server.dart';

/// Batas waktu tiap permintaan ke server (keputusan owner 2026-10-04).
///
/// Tanpa batas, permintaan yang terkirim saat sinyal ada tapi internet mati
/// menunggu sampai Android menyerah — bisa beberapa menit. Selama itu
/// putaran sinkron tidak pernah selesai, dan karena semua sinkron
/// berikutnya (termasuk yang otomatis) ikut menunggu putaran yang sama,
/// HP berhenti sinkron sampai aplikasinya ditutup.
const batasPermintaan = Duration(seconds: 15);

/// Berapa lama sambungan ke server dibiarkan terbuka saat tidak dipakai.
///
/// Bawaan Dart 15 detik. Kasir biasanya butuh lebih lama dari itu antara
/// membuka keranjang dan menekan Konfirmasi pembayaran, jadi pertanyaan ke
/// server saat bayar selalu harus membuka sambungan baru dulu — diukur di
/// emulator 12 Nov 2026: 0,8–1 detik, padahal pertanyaannya sendiri ±60 ms.
/// Dengan 2 menit, 8 kali bayar open bill berturut-turut: nilai tengah
/// ±0,1 detik. Laporan "HP ini masih aktif" tiap menit ikut menjaga
/// sambungannya tetap hangat selama aplikasi dipakai.
const umurSambunganDiam = Duration(minutes: 2);

/// Klien HTTP dasar untuk Supabase — lihat [umurSambunganDiam].
http.Client klienDasar() =>
    IOClient(HttpClient()..idleTimeout = umurSambunganDiam);

/// Kecepatan kirim paling lambat yang masih ditunggu, dalam bita per detik.
/// Sedikit di bawah jaringan GSM (sekitar 1,8 KB/s).
const kecepatanKirimMinimum = 1024;

/// Klien HTTP untuk Supabase yang menyerah setelah [batas]. Satu tempat
/// untuk semua permintaan: data, login, dan foto.
///
/// Yang dibatasi adalah waktu sampai server MULAI menjawab, lalu jeda antar
/// potongan data sesudahnya. Data yang masih mengalir (mis. foto besar di
/// jaringan lambat) tidak diputus di tengah; yang berhenti mengalir [batas]
/// lamanya diputus. Dulu jawaban yang macet di tengah ditunggu selamanya:
/// putaran sinkron tidak pernah selesai, dan laporan "shift dilepas" sesudah
/// keluar karena diam tidak pernah terkirim (review 3 Nov).
///
/// Waktu mengirim ikut dihitung sampai server menjawab, jadi batasnya
/// ditambah sesuai ukuran kiriman. Dulu foto 64 KB di sinyal GSM butuh 36
/// detik dan selalu diputus di detik ke-15, jadi tidak pernah sampai ke HP
/// lain. Kemajuan per potongan tidak bisa dipakai sebagai gantinya: fotonya
/// langsung masuk penyangga jaringan HP, jadi kelihatan selesai terkirim.
class KlienBerbatasWaktu extends http.BaseClient {
  final http.Client _dalam;
  final Duration batas;
  final int kecepatanMinimum;

  KlienBerbatasWaktu(
    this._dalam, {
    this.batas = batasPermintaan,
    this.kecepatanMinimum = kecepatanKirimMinimum,
  });

  /// Selama jam HP salah, SDK Supabase menganggap setiap tiket sudah mati dan
  /// menukarnya sebelum SETIAP permintaan. Satu sinkron saja bisa menabrak
  /// batas server (429), dan batas itu berlaku per alamat internet, jadi HP
  /// lain di WiFi yang sama ikut kena.
  ///
  /// Karena itu jawaban penukaran terakhir dipakai ulang selama tiketnya masih
  /// hidup menurut JAM SERVER. Tiap tukar server memberi tiket pengganti
  /// baru, dan SDK lalu menukar tiket pengganti itu — jadi yang dicocokkan
  /// tiket lama ATAU tiket pengganti dari jawaban itu. Dulu hanya isi
  /// permintaan yang sama persis, yang tidak pernah terjadi (audit 6 Nov
  /// nomor 8).
  _TukarTerakhir? _tukarTerakhir;

  /// Sesudah server menjawab 429, penukaran ditahan selama ini tanpa
  /// menghubungi server (audit 6 Nov nomor 9). SDK mengulang jawaban 5xx
  /// sampai ±6 kali dalam 10 detik; tanpa penahan, satu penolakan berubah
  /// jadi enam permintaan dan batas server makin lama lepas.
  static const tahanSesudahDibatasi = Duration(minutes: 1);
  Stopwatch? _sejakDibatasi;

  static bool _tukarTiket(http.BaseRequest r) =>
      r.method == 'POST' &&
      r.url.path.endsWith('/auth/v1/token') &&
      r.url.queryParameters['grant_type'] == 'refresh_token';

  static String? _tiketDiminta(String isi) {
    try {
      final data = jsonDecode(isi);
      return data is Map ? data['refresh_token'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// Jawaban pengganti 503: SDK menganggapnya gangguan sementara, jadi
  /// tiketnya tidak dihapus.
  static http.StreamedResponse _sedangDibatasi(http.BaseRequest request) {
    final isi = utf8.encode('{"msg":"dibatasi sementara"}');
    return http.StreamedResponse(
      Stream.value(isi),
      503,
      contentLength: isi.length,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }

  Duration _batasKirim(int? ukuran) =>
      batas +
      Duration(
        milliseconds: ((ukuran ?? 0) * 1000 / kecepatanMinimum).ceil(),
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final tukar = _tukarTiket(request);
    final isiTukar = tukar && request is http.Request ? request.body : null;
    final tiket = isiTukar == null ? null : _tiketDiminta(isiTukar);
    if (tukar) {
      final dibatasi = _sejakDibatasi;
      if (dibatasi != null && dibatasi.elapsed < tahanSesudahDibatasi) {
        return _sedangDibatasi(request);
      }
      final simpanan = _tukarTerakhir;
      if (tiket != null &&
          simpanan != null &&
          JamServer.instance.jamSalah &&
          simpanan.cocok(tiket) &&
          simpanan.masihHidup(JamServer.instance.sekarang())) {
        return simpanan.jawaban(request);
      }
    }

    if (tukar) debugPrint('[sesi] tukar tiket ke server');
    final batasKirim = _batasKirim(request.contentLength);
    final r = await _dalam
        .send(request)
        .timeout(
          batasKirim,
          onTimeout: () => throw TimeoutException(
            'Server tidak menjawab dalam ${batasKirim.inSeconds} detik',
            batasKirim,
          ),
        );
    JamServer.instance.catat(r.headers['date']);
    // Server sedang membatasi permintaan. SDK menganggap semua penolakan saat
    // menukar sebagai tiket tidak sah, lalu MENGHAPUS tiketnya, padahal tiket
    // itu satu-satunya identitas HP ini dan tidak bisa pulih sendiri. Kode 5xx
    // dianggapnya gangguan sementara: tiketnya disimpan dan dicoba lagi.
    if (tukar && r.statusCode == 429) {
      _sejakDibatasi = Stopwatch()..start();
      await r.stream.drain<void>();
      return _sedangDibatasi(request);
    }
    if (tiket != null && r.statusCode == 200 && JamServer.instance.jamSalah) {
      final isi = await r.stream.toBytes().timeout(batas);
      final baru = _TukarTerakhir.dari(tiket, isi, r.headers);
      if (baru != null) {
        _tukarTerakhir = baru;
        return baru.jawaban(request);
      }
      return _apaAdanya(r, isi);
    }
    return http.StreamedResponse(
      r.stream.timeout(
        batas,
        onTimeout: (sink) {
          sink.addError(
            TimeoutException(
              'Kiriman server berhenti di tengah jalan '
              '${batas.inSeconds} detik',
              batas,
            ),
          );
          sink.close();
        },
      ),
      r.statusCode,
      contentLength: r.contentLength,
      request: r.request,
      headers: r.headers,
      isRedirect: r.isRedirect,
      persistentConnection: r.persistentConnection,
      reasonPhrase: r.reasonPhrase,
    );
  }

  static http.StreamedResponse _apaAdanya(
    http.StreamedResponse r,
    List<int> isi,
  ) =>
      http.StreamedResponse(
        Stream.value(isi),
        r.statusCode,
        contentLength: isi.length,
        request: r.request,
        headers: r.headers,
      );

  @override
  void close() => _dalam.close();
}

class _TukarTerakhir {
  final String tiketLama;
  final String tiketBaru;

  /// Kapan tiket akses di jawaban ini mati, menurut server.
  final DateTime kedaluwarsa;
  final List<int> isi;
  final Map<String, String> header;

  _TukarTerakhir._(
    this.tiketLama,
    this.tiketBaru,
    this.kedaluwarsa,
    this.isi,
    this.header,
  );

  /// Null kalau jawabannya tidak bisa dibaca — tidak disimpan.
  static _TukarTerakhir? dari(
    String tiketLama,
    List<int> isi,
    Map<String, String> header,
  ) {
    try {
      final data = jsonDecode(utf8.decode(isi)) as Map<String, dynamic>;
      final baru = data['refresh_token'] as String;
      final akses = (data['access_token'] as String).split('.');
      final muatan = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(akses[1]))),
      ) as Map<String, dynamic>;
      final exp = (muatan['exp'] as num).toInt();
      return _TukarTerakhir._(
        tiketLama,
        baru,
        DateTime.fromMillisecondsSinceEpoch(exp * 1000),
        isi,
        header,
      );
    } catch (_) {
      return null;
    }
  }

  bool cocok(String tiket) => tiket == tiketLama || tiket == tiketBaru;

  /// Sisa semenit dianggap mati, supaya ditukar sungguhan sebelum habis.
  bool masihHidup(DateTime jamServer) =>
      jamServer.add(const Duration(minutes: 1)).isBefore(kedaluwarsa);

  http.StreamedResponse jawaban(http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(isi),
        200,
        contentLength: isi.length,
        request: request,
        headers: header,
      );
}
