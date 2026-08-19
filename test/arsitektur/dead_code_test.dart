import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menolak file di `lib/` yang tidak dipakai siapa pun (dead code).
///
/// Latar belakang — permintaan "hapus 3 card statistik" dulu hanya dikerjakan
/// separuh: widget-nya dilepas dari dashboard, tapi ketiga filenya dibiarkan.
/// Dari sisi tampilan permintaannya terpenuhi, jadi tidak ada yang sadar bahwa
/// 820 baris kode mati tertinggal. Baru ketahuan dua bulan kemudian, dan
/// sempat ikut dimigrasi lagi saat refactor repository.
///
/// "Hilang dari UI" itu terlihat dan gampang diverifikasi; "file terhapus"
/// tidak terlihat. Test ini yang menjadikannya terlihat.
void main() {
  /// File yang memang tidak dirujuk nama deklarasinya, tapi BUKAN dead code.
  /// Kalau menambah entri di sini, tulis alasannya.
  const diizinkan = <String, String>{
    'lib/main.dart': 'entry point — dipanggil Flutter, bukan dirujuk file lain',
  };

  /// Nama deklarasi tingkat atas yang diekspor sebuah file Dart.
  Set<String> deklarasi(String isi) {
    final nama = <String>{};
    final pola = [
      RegExp(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+)*class\s+(\w+)',
          multiLine: true),
      RegExp(r'^mixin\s+(\w+)', multiLine: true),
      RegExp(r'^enum\s+(\w+)', multiLine: true),
      RegExp(r'^extension\s+(\w+)', multiLine: true),
      RegExp(r'^typedef\s+(\w+)', multiLine: true),
      // Fungsi tingkat atas, mis. `Future<void> showFoo(...)` atau `int bar()`
      RegExp(r'^[A-Za-z_][\w<>,\s\?\[\]]*\s+(\w+)\s*\(', multiLine: true),
      // Variabel/konstanta tingkat atas
      RegExp(r'^(?:final|const)\s+[\w<>,\s\?\[\]]*?(\w+)\s*=', multiLine: true),
    ];
    for (final p in pola) {
      for (final m in p.allMatches(isi)) {
        final n = m.group(1);
        if (n != null && n.isNotEmpty && !n.startsWith('_')) nama.add(n);
      }
    }
    return nama;
  }

  test('tidak ada file di lib/ yang tidak dipakai siapa pun', () {
    final berkas = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();

    // Muat sekali, dipakai berulang.
    final isiLib = {for (final f in berkas) f.path: f.readAsStringSync()};
    final isiTest = <String, String>{
      for (final f in Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };

    final yatim = <String>[];

    for (final f in berkas) {
      final path = f.path.replaceAll(r'\', '/');
      if (diizinkan.containsKey(path)) continue;

      final nama = deklarasi(isiLib[f.path]!);
      if (nama.isEmpty) continue;

      // Dipakai kalau salah satu nama deklarasinya muncul di file LAIN.
      final dipakai = nama.any((n) {
        final ref = RegExp(r'\b' + RegExp.escape(n) + r'\b');
        bool adaDi(Map<String, String> kumpulan) => kumpulan.entries
            .any((e) => e.key != f.path && ref.hasMatch(e.value));
        return adaDi(isiLib) || adaDi(isiTest);
      });

      if (!dipakai) yatim.add(path);
    }

    expect(
      yatim,
      isEmpty,
      reason: 'File di atas tidak dirujuk file mana pun. Kalau memang sudah '
          'tidak dipakai, HAPUS filenya — jangan cuma dilepas dari UI. Kalau '
          'sebenarnya terpakai lewat cara yang tidak terdeteksi, tambahkan ke '
          'map `diizinkan` beserta alasannya.',
    );
  });
}
