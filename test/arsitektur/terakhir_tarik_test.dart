import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menjaga pemisahan "HP masih dipakai" (`terakhir_aktif`) dari "HP sudah
/// menerima semua data" (`terakhir_tarik`), patokan buang sampah.
///
/// Perilakunya diuji di PostgreSQL sungguhan saat berkasnya ditulis (9
/// skenario, termasuk sabotase penjaga kolom kosong). Yang dikunci di sini
/// adalah hal yang gampang rusak tanpa gejala saat disunting kelak.
void main() {
  String kode(String jalur) => File(jalur)
      .readAsLinesSync()
      .where((b) => !b.trimLeft().startsWith('--'))
      .join('\n');

  test('laporan hadir biasa (sentuhan, sinkron gagal) tidak memajukan '
      'terakhir_tarik', () {
    final sql = kode('supabase/perangkat_tarik.sql');
    expect(sql, contains('p_tarik_bersih boolean default false'));
    expect(sql, contains('when p_tarik_bersih then now()'));
    expect(sql, contains('drop function if exists public.perangkat_hadir(uuid)'),
        reason: 'versi lama dibuang supaya pemanggilan tidak ambigu');
  });

  test('buang sampah memakai terakhir_tarik, dan HP yang kolomnya kosong '
      'menahan pembuangan', () {
    final sql = kode('supabase/buang_sampah_tarik.sql');
    expect(sql, contains('bool_and(terakhir_tarik is not null)'),
        reason: 'min() mengabaikan kosong — tanpa ini HP lama tidak menahan');
    expect(sql, contains('min(terakhir_tarik)'));
    expect(sql, isNot(contains('terakhir_aktif')));
    expect(sql, contains('from anon, authenticated'));
  });

  test('aplikasi hanya melapor tarikan bersih lewat aturan tarikBersih', () {
    final layanan = File('lib/data/sync/sync_service.dart').readAsStringSync();
    expect(layanan, contains('tarikBersih: tarikBersih(hasil, jumlahTertahan.value)'));
    final otomatis = File('lib/data/sync/sync_otomatis.dart').readAsStringSync();
    expect(otomatis, isNot(contains('tarikBersih:')),
        reason: 'laporan dari sentuhan bukan tarikan');
  });
}
