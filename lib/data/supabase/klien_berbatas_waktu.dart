import 'dart:async';

import 'package:http/http.dart' as http;

import 'jam_server.dart';

/// Batas waktu tiap permintaan ke server (keputusan owner 2026-10-04).
///
/// Tanpa batas, permintaan yang terkirim saat sinyal ada tapi internet mati
/// menunggu sampai Android menyerah — bisa beberapa menit. Selama itu
/// putaran sinkron tidak pernah selesai, dan karena semua sinkron
/// berikutnya (termasuk yang otomatis) ikut menunggu putaran yang sama,
/// HP berhenti sinkron sampai aplikasinya ditutup.
const batasPermintaan = Duration(seconds: 15);

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
  /// lain di WiFi yang sama ikut kena. Karena itu jawaban penukaran terakhir
  /// dipakai ulang selama [umurTukarUlang].
  static const umurTukarUlang = Duration(minutes: 5);
  _TukarTerakhir? _tukarTerakhir;

  static bool _tukarTiket(http.BaseRequest r) =>
      r.method == 'POST' &&
      r.url.path.endsWith('/auth/v1/token') &&
      r.url.queryParameters['grant_type'] == 'refresh_token';

  Duration _batasKirim(int? ukuran) =>
      batas +
      Duration(
        milliseconds: ((ukuran ?? 0) * 1000 / kecepatanMinimum).ceil(),
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final tukar = _tukarTiket(request);
    final isiTukar = tukar && request is http.Request ? request.body : null;
    final simpanan = _tukarTerakhir;
    if (isiTukar != null &&
        simpanan != null &&
        JamServer.instance.jamSalah &&
        simpanan.isiPermintaan == isiTukar &&
        simpanan.umur.elapsed < umurTukarUlang) {
      return simpanan.jawaban(request);
    }

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
      return http.StreamedResponse(
        r.stream,
        503,
        contentLength: r.contentLength,
        request: r.request,
        headers: r.headers,
      );
    }
    if (isiTukar != null && r.statusCode == 200 && JamServer.instance.jamSalah) {
      final isi = await r.stream.toBytes().timeout(batas);
      final baru = _TukarTerakhir(isiTukar, isi, r.headers);
      _tukarTerakhir = baru;
      return baru.jawaban(request);
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

  @override
  void close() => _dalam.close();
}

class _TukarTerakhir {
  final String isiPermintaan;
  final List<int> isi;
  final Map<String, String> header;

  /// Stopwatch, bukan jam HP: jam HP-nya justru yang sedang salah.
  final Stopwatch umur = Stopwatch()..start();

  _TukarTerakhir(this.isiPermintaan, this.isi, this.header);

  http.StreamedResponse jawaban(http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(isi),
        200,
        contentLength: isi.length,
        request: request,
        headers: header,
      );
}
