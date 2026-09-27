import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menjaga aturan akses di `supabase/` tidak diam-diam melonggar.
///
/// ── KENAPA PENJAGA INI ADA ──
///
/// `supabase/izin.sql` pernah membuat sendiri policy tulis untuk
/// `user_permissions` berbunyi `with check (true)`. `perangkat_tegakkan.sql`
/// menimpanya dengan `public.perangkat_aktif()`, jadi di server hasil akhirnya
/// benar — SELAMA urutan menjalankannya benar.
///
/// Masalahnya `izin.sql` wajar dijalankan ulang (menambah izin baru ke
/// katalog). Sekali dijalankan ulang sesudah penegakan menyala, ia menimpa
/// balik versi ketat itu dengan versi longgar: tanpa galat, tanpa gejala, dan
/// perangkat yang sudah DICABUT bisa mengubah izin lagi.
///
/// Kerusakan yang tidak bersuara seperti itu tidak akan ketahuan sampai ada
/// yang menyalahgunakannya. Maka dikunci di sini, bukan diingat-ingat.
void main() {
  final berkas = Directory('supabase')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Buang baris komentar, lalu pecah jadi pernyataan per `;`.
  ///
  /// Komentar dibuang lebih dulu supaya catatan yang MENJELASKAN kenapa
  /// sesuatu longgar tidak ikut terhitung sebagai pelanggaran — penjaga yang
  /// menghukum dokumentasi yang baik akan dimatikan orang, bukan diperbaiki.
  List<String> pernyataan(File f) {
    final kode = f
        .readAsLinesSync()
        .where((b) => !b.trimLeft().startsWith('--'))
        .join('\n');
    return kode.split(';');
  }

  test('tidak ada policy longgar selain `baca_perangkat` yang disengaja', () {
    final longgar = RegExp(
      r'using\s*\(\s*true\s*\)|with\s+check\s*\(\s*true\s*\)',
      caseSensitive: false,
    );
    final pelanggar = <String>[];

    for (final f in berkas) {
      for (final p in pernyataan(f)) {
        if (!p.toLowerCase().contains('create policy')) continue;
        if (!longgar.hasMatch(p)) continue;

        // Satu-satunya yang boleh: daftar perangkat itu sendiri. Perangkat
        // yang barisnya hilang HARUS tetap bisa membacanya — di situlah ia
        // tahu dirinya belum terdaftar lalu memunculkan layar kunci. Kalau
        // ini ikut dikunci `perangkat_aktif()`, tidak ada jalan pulang.
        if (p.contains('public.perangkat')) continue;

        final nama = RegExp(r'create policy\s+(\w+)', caseSensitive: false)
            .firstMatch(p)
            ?.group(1);
        pelanggar.add('${f.path}: ${nama ?? p.trim().split('\n').first}');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Policy ini memakai `true`, bukan `public.perangkat_aktif()` — '
          'artinya perangkat yang sudah DICABUT tetap boleh melakukannya. '
          'Pakai `public.perangkat_aktif()`, atau kalau memang disengaja, '
          'longgarkan penjaga ini berikut alasannya.',
    );
  });

  test('tidak ada policy DELETE untuk tabel data', () {
    // Seluruh penghapusan BARIS di aplikasi ini lunak (`deleted_at` diisi
    // lewat UPDATE). Tidak ada satu pun jalur kode yang mengirim DELETE ke
    // tabel, jadi larangan ini tidak menghalangi apa pun yang sah — tapi
    // menutup kerusakan yang TIDAK BISA dipulihkan kalau kunci bocor.
    //
    // BERKAS di storage adalah urusan lain dan sengaja dikecualikan:
    // `sync_gambar.dart` memang membuang foto yatim — berkas yang tidak
    // dirujuk baris mana pun. Tanpa itu kuota Storage terisi sampah selamanya.
    final pelanggar = <String>[];

    for (final f in berkas) {
      for (final p in pernyataan(f)) {
        final k = p.toLowerCase();
        if (!k.contains('create policy')) continue;
        if (k.contains('storage.objects')) continue;
        if (!RegExp(r'for\s+delete|for\s+all').hasMatch(k)) continue;

        final nama = RegExp(r'create policy\s+(\w+)', caseSensitive: false)
            .firstMatch(p)
            ?.group(1);
        pelanggar.add('${f.path}: ${nama ?? p.trim().split('\n').first}');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Policy DELETE (atau FOR ALL yang mencakupnya) membuat data bisa '
          'dilenyapkan permanen dari perangkat. Data yang dikotori masih bisa '
          'dibenahi; data yang dihapus tidak.',
    );
  });
}
