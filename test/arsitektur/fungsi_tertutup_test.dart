import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Setiap fungsi di server harus tertutup untuk yang belum login (`anon`).
///
/// ── KENAPA PENJAGA INI ADA ──
///
/// Pemeriksaan 2026-10-24 menemukan 11 fungsi yang bisa dipanggil siapa pun
/// di internet tanpa login — termasuk `daftarkan_perangkat`, sehingga kunci
/// pemasangan bisa dicoba tanpa batas. Penyebabnya: berkas-berkas lama
/// hanya menulis `revoke ... from public`, padahal Supabase memberi hak ke
/// `anon` secara LANGSUNG.
///
/// supabase/perangkat_aman.sql menutup semua fungsi yang sudah ada. Tapi
/// PostgreSQL selalu memberi hak PUBLIC ke fungsi BARU, dan itu tidak bisa
/// dicegah dari pengaturan skema. Maka setiap berkas yang membuat fungsi
/// sesudahnya wajib menutup fungsinya sendiri.
void main() {
  /// Berkas yang sudah ada saat perangkat_aman.sql ditulis: fungsinya ikut
  /// ditutup oleh perulangan di sana. `create or replace` mempertahankan hak
  /// yang ada, jadi menjalankan ulang berkas ini tidak membukanya lagi.
  const sebelumPenutupan = {
    'buang_sampah.sql',
    'nomor_nota.sql',
    'kategori_terhapus.sql',
    'open_bill_kunci.sql',
    'perangkat.sql',
    'perangkat_model.sql',
    'perangkat_shift.sql',
    'perangkat_tegakkan.sql',
    'shift_pemegang_basi.sql',
    'sync_urutan.sql',
  };

  test('fungsi baru menulis revoke ... from public, anon', () {
    final pelanggar = <String>[];
    for (final f in Directory('supabase').listSync().whereType<File>()) {
      final nama = f.uri.pathSegments.last;
      if (!nama.endsWith('.sql') || sebelumPenutupan.contains(nama)) continue;
      final kode = f
          .readAsLinesSync()
          .where((b) => !b.trimLeft().startsWith('--'))
          .join('\n')
          .toLowerCase();
      final dibuat = RegExp(
        r'create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)',
      ).allMatches(kode).map((m) => m.group(1)!).toSet();
      for (final fn in dibuat) {
        final tertutup = RegExp(
          'revoke[^;]*function\\s+public\\.$fn\\b[^;]*from[^;]*\\banon\\b',
        ).hasMatch(kode);
        if (!tertutup) pelanggar.add('$nama: $fn');
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'tambahkan: revoke all on function public.<nama>(...) '
            'from public, anon;');
  });

  test('perangkat_aman.sql mencabut public DAN anon untuk semua fungsi', () {
    final kode = File('supabase/perangkat_aman.sql').readAsStringSync();
    expect(kode, contains("'revoke execute on function %s from public, anon'"));
    expect(kode, contains("'grant execute on function %s to authenticated'"),
        reason: 'fungsi yang sudah dipakai HP login tidak boleh putus');
  });
}
