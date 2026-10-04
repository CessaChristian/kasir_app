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
/// Yang dibatasi adalah waktu sampai server MULAI menjawab. Data yang sudah
/// mengalir (mis. foto besar di jaringan lambat) tidak diputus di tengah.
class KlienBerbatasWaktu extends http.BaseClient {
  final http.Client _dalam;
  final Duration batas;

  KlienBerbatasWaktu(this._dalam, {this.batas = batasPermintaan});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _dalam
      .send(request)
      .timeout(
        batas,
        onTimeout: () => throw TimeoutException(
          'Server tidak menjawab dalam ${batas.inSeconds} detik',
          batas,
        ),
      );

  @override
  void close() => _dalam.close();
}
