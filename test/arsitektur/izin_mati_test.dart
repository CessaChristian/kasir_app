import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mencegah izin peninggalan arsitektur multi-bisnis muncul lagi.
///
/// `manage_business` dan `switch_business` mengatur pemilihan usaha aktif —
/// fitur yang dihapus seluruhnya di v13. Tapi keduanya tertinggal di dua
/// tempat sampai v19: daftar izin owner di `SessionManager`, dan data seed
/// `permissions` yang disemai ke SETIAP pemasangan baru.
///
/// Kenapa ini layak dijaga, bukan sekadar dirapikan: izin yang tidak menjaga
/// apa pun tetap muncul di halaman Kelola Izin dan bisa dinyalakan owner.
/// Kasir yang diberi izin itu tidak mendapat kemampuan apa-apa — tapi
/// tampilannya menjanjikan sesuatu yang tidak ada. Sisa seperti ini juga yang
/// membuat orang menebak-nebak apakah fiturnya masih ada.
void main() {
  const mati = ['manage_business', 'switch_business'];

  test('tidak ada izin arsitektur multi-bisnis yang tersisa di kode', () {
    final pelanggar = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;

      final isi = entity.readAsStringSync();
      for (final kode in mati) {
        if (!isi.contains(kode)) continue;
        // Migrasi WAJIB menyebut namanya — itu justru yang membuangnya dari
        // database yang sudah terlanjur menyemainya.
        if (entity.path.endsWith('app_database.dart') &&
            isi.contains('DELETE FROM permissions')) {
          continue;
        }
        pelanggar.add('${entity.path} -> $kode');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Izin ini tidak menjaga apa pun sejak arsitektur multi-bisnis '
          'dihapus di v13. Membiarkannya membuat halaman Kelola Izin '
          'menawarkan sesuatu yang tidak ada.',
    );
  });

  test('dokumentasi tidak lagi menjanjikan fitur usaha yang sudah dihapus', () {
    final pelanggar = <String>[];

    for (final entity in Directory('docs').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      // `docs/superpowers/` adalah ARSIP rencana lama, bukan dokumentasi
      // hidup — isinya catatan sejarah era multi-bisnis dan memang seharusnya
      // menyebut fitur yang sudah dihapus. Berkasnya juga tidak masuk git.
      // Yang dijaga di sini hanya dokumen yang dibaca orang sebagai penjelasan
      // keadaan SEKARANG.
      if (entity.path.contains('superpowers')) continue;
      final isi = entity.readAsStringSync();
      for (final kode in [...mati, 'BusinessSwitcher', 'features/business']) {
        if (isi.contains(kode)) pelanggar.add('${entity.path} -> $kode');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Dokumen yang menjelaskan fitur yang sudah tidak ada lebih '
          'buruk daripada tidak ada dokumen: pembacanya mencari kode yang '
          'tidak akan pernah ketemu.',
    );
  });
}
