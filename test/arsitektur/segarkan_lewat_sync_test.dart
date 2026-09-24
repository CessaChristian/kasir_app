import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Setiap tarik-segarkan harus benar-benar menghubungi server.
///
/// ── MASALAH YANG DIKUNCI ──
///
/// Halaman "Pantau Shift" dulu memakai `RefreshIndicator` sendiri dengan
/// `onRefresh` yang hanya membaca ulang database LOKAL. Gerakannya terasa,
/// animasinya berputar, lalu berhenti — dan pemilik menyimpulkan datanya
/// memang sudah yang terbaru. Padahal server tidak pernah ditanya.
///
/// Itu lebih buruk daripada tidak punya tarik-segarkan sama sekali: yang
/// tidak ada membuat orang mencari cara lain, yang palsu membuat orang
/// berhenti mencari.
///
/// [SyncRefresh] melakukan keduanya — menyinkronkan lalu memuat ulang — dan
/// sekalian memberi pesan yang jujur saat gagal. Jadi semua halaman memakai
/// itu, bukan RefreshIndicator telanjang.
void main() {
  test('tidak ada halaman yang memakai RefreshIndicator sendiri', () {
    final pelanggar = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Satu-satunya tempat yang BOLEH memakainya: pembungkusnya sendiri.
      if (f.path.endsWith('sync_refresh.dart')) continue;

      // Baris komentar dibuang dulu. Tanpa ini, catatan yang MENJELASKAN
      // kenapa RefreshIndicator tidak dipakai justru ikut dihitung sebagai
      // pelanggaran — dan penjaganya menghukum dokumentasi yang baik.
      final kode = f
          .readAsLinesSync()
          .where((b) => !b.trimLeft().startsWith('//'))
          .join('\n');

      // Dicari pemanggilannya, bukan sekadar namanya.
      if (kode.contains('RefreshIndicator(')) pelanggar.add(f.path);
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Pakai SyncRefresh, bukan RefreshIndicator langsung. Tanpa itu '
          'tarikan layarnya cuma memuat ulang data lokal — terlihat bekerja, '
          'padahal server tidak pernah ditanya.',
    );
  });
}
