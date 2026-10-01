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

  test('setiap tabel yang dibuat ikut dicabut haknya di rls.sql', () {
    // ── KENAPA PENJAGA INI ADA ──
    //
    // Daftar tabel di `rls.sql` ditulis tangan, dan `rahasia` sempat
    // terlewat — justru tabel yang menyimpan sidik jari kunci pemasangan.
    // Alasan melewatkannya waktu itu: "toh RLS-nya sudah nol policy". Itu
    // keliru, dan persis alasan yang dibantah berkas itu sendiri.
    //
    // Kelalaian jenis ini tidak bisa ketahuan sendiri: tidak ada gejala,
    // tidak ada galat, dan baru berbahaya kalau suatu hari tabelnya diberi
    // policy. Maka dibandingkan otomatis, bukan diingat-ingat.
    final pembuat = ['supabase/schema.sql', 'supabase/perangkat.sql'];

    String tanpaKomentar(String path) => File(path)
        .readAsLinesSync()
        .where((b) => !b.trimLeft().startsWith('--'))
        .join('\n');

    final dibuat = <String>{};
    for (final f in pembuat) {
      final r = RegExp(
        r'create table\s+(?:if not exists\s+)?public\.(\w+)',
        caseSensitive: false,
      );
      for (final m in r.allMatches(tanpaKomentar(f))) {
        dibuat.add(m.group(1)!);
      }
    }

    // Sanity: kalau regexnya berhenti cocok, penjaganya jadi lulus palsu.
    expect(dibuat.length, greaterThanOrEqualTo(10),
        reason: 'Pembacaan `create table` gagal — penjaga ini jadi tak berguna');

    final rls = tanpaKomentar('supabase/rls.sql');
    final terlewat = dibuat
        .where((t) => !rls.contains("'$t'") && !rls.contains('public.$t'))
        .toList()
      ..sort();

    expect(
      terlewat,
      isEmpty,
      reason: 'Tabel ini dibuat tapi tidak disebut sama sekali di '
          'supabase/rls.sql, jadi hak anon/authenticated-nya tidak pernah '
          'dicabut. Tambahkan ke blok revoke — DELETE untuk tabel data, atau '
          '`revoke all` kalau tabelnya murni milik server.',
    );
  });

  test('buang_sampah tidak bisa dipanggil dari HP', () {
    // ── KENAPA PENJAGA INI ADA ──
    //
    // `buang_sampah` menghapus PERMANEN dan berjalan sebagai pemilik
    // database, jadi tidak terhalang pencabutan hak DELETE untuk HP.
    // Supabase otomatis memberi hak EXECUTE ke `anon` dan `authenticated`
    // untuk setiap fungsi baru di skema public — kalau pencabutannya hilang,
    // HP mana pun, termasuk yang kuncinya bocor, bisa memicu pembuangan
    // lewat API dengan jeda nol.
    final isi = File('supabase/buang_sampah.sql')
        .readAsLinesSync()
        .where((b) => !b.trimLeft().startsWith('--'))
        .join('\n')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');

    expect(
      isi,
      contains('revoke all on function public.buang_sampah(interval) '
          'from anon, authenticated'),
      reason: 'hak memanggil buang_sampah harus dicabut dari anon dan '
          'authenticated — hanya dashboard dan pg_cron yang boleh',
    );
    expect(
      RegExp(r'grant\s+\w+\s+on\s+function\s+public\.buang_sampah')
          .hasMatch(isi),
      isFalse,
      reason: 'buang_sampah tidak boleh diberi hak ke peran mana pun',
    );
  });
}
