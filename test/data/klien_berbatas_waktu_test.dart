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
}
