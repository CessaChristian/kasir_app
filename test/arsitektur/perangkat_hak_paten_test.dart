import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mengunci keputusan: pengelolaan PERANGKAT adalah hak paten pemilik.
///
/// ── KENAPA TIDAK BOLEH JADI IZIN ──
///
/// Izin di aplikasi ini bisa dinyalakan pemilik untuk kasir mana pun lewat
/// halaman Kelola Izin. Yang diatur di sini beda tingkat: perangkat mana yang
/// boleh menyentuh data toko sama sekali.
///
/// Kalau ini jadi izin biasa, pemilik bisa menyalakannya untuk kasir — lalu
/// kasir bisa melepaskan perangkat pemilik, dan pagarnya kehilangan arti.
/// Maka pagarnya `isOwner`, yang tidak bisa diberikan kepada siapa pun.
void main() {
  test('tidak ada izin perangkat di katalog izin', () {
    // Katalognya ditulis sebagai daftar `'code': '...'` di dalam
    // _seedPermissions, jadi yang dibaca kode sumbernya.
    final db = File('lib/data/app_database.dart').readAsStringSync();
    final awal = db.indexOf('const permissionsData = [');
    expect(awal, isNot(-1), reason: 'katalog izin harus ada');
    final katalog = db.substring(awal, db.indexOf('];', awal)).toLowerCase();

    for (final terlarang in const ['perangkat', 'device', 'lepas']) {
      expect(
        katalog.contains("'code': '") && katalog.contains(terlarang),
        isFalse,
        reason: 'Pengelolaan perangkat tidak boleh muncul sebagai izin yang '
            'bisa diberikan ke kasir. Pagarnya isOwner.',
      );
    }
  });

  test('menu Daftar Perangkat dipagari isOwner, bukan hasPermission', () {
    final isi = File('lib/app/app_shell.dart').readAsStringSync();

    // Yang dicari MENUNYA, bukan teks lain yang kebetulan memuat kalimat
    // serupa di tempat lain dalam berkas.
    final i = isi.indexOf("label: 'Daftar Perangkat'");
    expect(i, isNot(-1), reason: 'menunya harus ada di drawer');

    // Cari pagar terdekat DI ATAS menunya.
    final sebelum = isi.substring(0, i);
    final posOwner = sebelum.lastIndexOf('isOwner');
    final posIzin = sebelum.lastIndexOf('hasPermission');

    expect(
      posOwner > posIzin,
      isTrue,
      reason: 'Menu Daftar Perangkat harus berada di dalam pagar isOwner. '
          'Kalau yang terdekat justru hasPermission, hak ini bisa diberikan '
          'ke kasir — dan itu yang tidak boleh.',
    );
  });
}
