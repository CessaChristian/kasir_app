import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasir_app/data/supabase/klien_berbatas_waktu.dart';

/// Setiap permintaan ke server menyerah setelah batas waktu (15 detik),
/// supaya putaran sinkron tidak menggantung dan menahan sinkron berikutnya.
void main() {
  test('batas bawaan 15 detik', () {
    expect(batasPermintaan, const Duration(seconds: 15));
  });

  test('server yang tidak menjawab → TimeoutException setelah batas', () async {
    final klien = KlienBerbatasWaktu(
      MockClient((_) => Completer<http.Response>().future),
      batas: const Duration(milliseconds: 50),
    );
    await expectLater(
      klien.get(Uri.parse('https://contoh.test/x')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('server yang menjawab cepat tidak terganggu', () async {
    final klien = KlienBerbatasWaktu(
      MockClient((_) async => http.Response('ok', 200)),
      batas: const Duration(seconds: 1),
    );
    final jawaban = await klien.get(Uri.parse('https://contoh.test/x'));
    expect(jawaban.body, 'ok');
  });

  test('jawaban yang macet di tengah jalan → TimeoutException, bukan '
      'menunggu selamanya', () async {
    final macet = StreamController<List<int>>();
    final klien = KlienBerbatasWaktu(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(macet.stream, 200),
      ),
      batas: const Duration(milliseconds: 50),
    );
    macet.add([1, 2, 3]); // sebagian foto sudah sampai, lalu berhenti
    await expectLater(
      klien.get(Uri.parse('https://contoh.test/foto.webp')),
      throwsA(isA<TimeoutException>()),
    );
    await macet.close();
  });

  test('data yang masih mengalir pelan tidak diputus', () async {
    final pelan = StreamController<List<int>>();
    final klien = KlienBerbatasWaktu(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(pelan.stream, 200),
      ),
      batas: const Duration(milliseconds: 80),
    );
    final jawaban = klien.get(Uri.parse('https://contoh.test/foto.webp'));
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      pelan.add([i]);
    }
    await pelan.close();
    expect((await jawaban).bodyBytes, [0, 1, 2, 3],
        reason: 'total 160 ms > batas, tapi tiap jeda < batas');
  });
}
