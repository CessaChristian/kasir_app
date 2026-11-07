import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Audit 6 Nov nomor 20: berkas SQL yang fungsinya didefinisikan ulang berkas
/// lebih baru tidak aman dijalankan ulang sendirian. Daftarnya di URUTAN.md
/// harus lengkap, supaya reset server tidak mundur diam-diam.
void main() {
  test('setiap berkas yang fungsinya digantikan tercantum di URUTAN.md', () {
    final urutan = File('supabase/URUTAN.md').readAsStringSync();
    final berkas = [
      for (final m in RegExp(r'^\| \d+ \| `([a-z_]+\.sql)`', multiLine: true)
          .allMatches(urutan))
        m.group(1)!,
    ];
    final pembuat = <String, List<String>>{};
    final pola = RegExp(r'create (?:or replace )?function\s+public\.([a-z_]+)');
    for (final f in berkas) {
      final isi = File('supabase/$f').readAsStringSync().toLowerCase();
      for (final m in pola.allMatches(isi)) {
        final daftar = pembuat.putIfAbsent(m.group(1)!, () => []);
        if (!daftar.contains(f)) daftar.add(f);
      }
    }
    final digantikan = {
      for (final d in pembuat.values)
        for (final f in d.take(d.length - 1)) f,
    };
    final bagian = urutan.substring(
      urutan.indexOf('Berkas yang sudah digantikan'),
      urutan.indexOf('Kalau terlanjur menjalankan'),
    );
    for (final f in digantikan) {
      expect(bagian, contains('| `$f` |'), reason: f);
    }
  });
}
