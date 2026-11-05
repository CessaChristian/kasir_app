import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kasir_app/data/supabase/klien_berbatas_waktu.dart';

/// Upload yang datanya masih mengalir tidak boleh dianggap macet: di sinyal
/// lemot, foto produk butuh lebih lama dari batas permintaan.
void main() {
  test('upload pelan yang terus mengalir tidak diputus', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      await r.drain<void>();
      r.response.statusCode = 200;
      await r.response.close();
    });

    final klien = KlienBerbatasWaktu(
      IOClient(),
      batas: const Duration(milliseconds: 300),
      kecepatanMinimum: 10,
    );
    addTearDown(klien.close);

    final minta = http.StreamedRequest(
      'POST',
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    minta.contentLength = 10;
    unawaited(() async {
      for (var i = 0; i < 10; i++) {
        minta.sink.add([i]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await minta.sink.close();
    }());

    final jawab = await klien.send(minta);
    expect(jawab.statusCode, 200);
  });

  test('kiriman yang servernya diam tetap diputus sesudah batas + ukuran', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async => r.drain<void>()); // tidak pernah menjawab

    final klien = KlienBerbatasWaktu(
      IOClient(),
      batas: const Duration(milliseconds: 100),
      kecepatanMinimum: 10,
    );
    addTearDown(klien.close);

    final minta = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:${server.port}/'),
    )..bodyBytes = [1, 2];
    final jam = Stopwatch()..start();
    await expectLater(klien.send(minta), throwsA(isA<TimeoutException>()));
    // 100 ms + 2 bita / 10 bita per detik = 300 ms.
    expect(jam.elapsedMilliseconds, inInclusiveRange(250, 1500));
  });
}
