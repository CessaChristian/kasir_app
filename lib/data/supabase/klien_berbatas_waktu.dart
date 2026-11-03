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

/// Klien HTTP untuk Supabase yang menyerah setelah [batas]. Satu tempat
/// untuk semua permintaan: data, login, dan foto.
///
/// Yang dibatasi adalah waktu sampai server MULAI menjawab, lalu jeda antar
/// potongan data sesudahnya. Data yang masih mengalir (mis. foto besar di
/// jaringan lambat) tidak diputus di tengah; yang berhenti mengalir [batas]
/// lamanya diputus. Dulu jawaban yang macet di tengah ditunggu selamanya:
/// putaran sinkron tidak pernah selesai, dan laporan "shift dilepas" sesudah
/// keluar karena diam tidak pernah terkirim (review 3 Nov).
class KlienBerbatasWaktu extends http.BaseClient {
  final http.Client _dalam;
  final Duration batas;

  KlienBerbatasWaktu(this._dalam, {this.batas = batasPermintaan});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await _dalam
        .send(request)
        .timeout(
          batas,
          onTimeout: () => throw TimeoutException(
            'Server tidak menjawab dalam ${batas.inSeconds} detik',
            batas,
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
