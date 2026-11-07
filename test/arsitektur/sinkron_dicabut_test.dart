import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Audit 6 Nov nomor 16: HP yang dicabut tidak boleh menjalankan mesin
/// sinkron. Server menjawab kosong untuk HP itu, dan jawaban kosong dibaca
/// "produk sudah dibuang": produk yang tertahan disembunyikan permanen.
void main() {
  test('status dicabut diperiksa sebelum mesin sinkron dibuat', () {
    final kode = File('lib/data/sync/sync_service.dart').readAsStringSync();
    final cek = kode.indexOf('status == StatusPerangkatIni.dicabut');
    final mesin = kode.indexOf('SyncEngine(db, onKemajuan:');
    expect(cek, isNot(-1));
    expect(mesin, greaterThan(cek));
    expect(kode.substring(cek, mesin), contains('return'),
        reason: 'HP yang dicabut berhenti, tidak lanjut ke mesin');
  });
}
