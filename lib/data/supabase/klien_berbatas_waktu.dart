import 'dart:async';

import 'package:http/http.dart' as http;

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

  Duration _batasKirim(int? ukuran) =>
      batas +
      Duration(
        milliseconds: ((ukuran ?? 0) * 1000 / kecepatanMinimum).ceil(),
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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
