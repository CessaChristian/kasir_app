import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/pemuat_terakhir.dart';

/// Revisi QA K6: dasbor owner sempat menampilkan angka lama.
void main() {
  test('yang dimulai dulu tapi selesai belakangan tidak menimpa', () async {
    final pemuat = PemuatTerakhir();
    final lama = Completer<int>();
    final baru = Completer<int>();
    final terpakai = <int>[];

    final a = pemuat.jalankan(() => lama.future, terpakai.add);
    final b = pemuat.jalankan(() => baru.future, terpakai.add);
    baru.complete(120000);
    await b;
    lama.complete(100000);
    await a;

    expect(terpakai, [120000]);
  });

  test('pemuatan berurutan semuanya dipakai', () async {
    final pemuat = PemuatTerakhir();
    final terpakai = <int>[];
    await pemuat.jalankan(() async => 1, terpakai.add);
    await pemuat.jalankan(() async => 2, terpakai.add);
    expect(terpakai, [1, 2]);
  });
}
