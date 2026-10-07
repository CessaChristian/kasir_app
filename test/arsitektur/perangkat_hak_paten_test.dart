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

  test('menu Perangkat & Kelola Kasir hanya terjangkau lewat kerangka owner',
      () {
    // Keduanya kini ada di tab Profil owner, bukan di drawer. Pagarnya
    // berlapis: AppShell memberi KerangkaOwner HANYA saat isOwner, dan
    // halaman Profil owner hanya dipasang oleh KerangkaOwner.
    final shell = File('lib/app/app_shell.dart').readAsStringSync();
    expect(shell.contains('DaftarPerangkatPage'), isFalse,
        reason: 'drawer kasir tidak boleh memuat menu Perangkat');
    expect(shell.contains('KelolaKasirPage'), isFalse,
        reason: 'drawer kasir tidak boleh memuat menu Kelola Kasir');

    final profil = File('lib/features/profil/pages/profil_owner_page.dart')
        .readAsStringSync();
    expect(profil.contains('DaftarPerangkatPage()'), isTrue);
    expect(profil.contains('KelolaKasirPage()'), isTrue);

    // Siapa saja yang memasang halaman Profil owner dan KerangkaOwner.
    List<String> pemakai(String nama) => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('$nama('))
        .map((f) => f.path)
        .toList();
    expect(pemakai('ProfilOwnerPage').where((p) => !p.endsWith('profil_owner_page.dart')),
        ['lib/app/kerangka_owner.dart']);
    expect(pemakai('KerangkaOwner').where((p) => !p.endsWith('kerangka_owner.dart')),
        ['lib/app/app_shell.dart']);
    expect(
        shell.contains(
            'if (SessionManager.instance.isOwner) return const KerangkaOwner();'),
        isTrue,
        reason: 'KerangkaOwner harus dipagari isOwner, bukan hasPermission');
  });
}
