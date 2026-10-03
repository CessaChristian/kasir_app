import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menolak permission yang dipakai sebagai **proksi role**.
///
/// Latar belakang — `dashboard_page.dart` pernah menulis:
///
/// ```dart
/// final isOwner = SessionManager.instance.hasPermission('manage_cashiers');
/// ```
///
/// Namanya `isOwner`, tapi isinya pertanyaan lain: "boleh kelola kasir?".
/// Dua hal berbeda dipaksa jadi satu. Karena `manage_cashiers` adalah baris di
/// tabel `permissions` yang bisa di-toggle owner untuk kasir mana pun, kasir
/// yang diberi izin itu ikut dianggap owner — lalu dashboard menampilkan kartu
/// "Pantau Shift" milik owner dan **kartu shift aktif kasirnya sendiri hilang**.
/// Bug ini bertahan tiga bulan karena tidak ada yang menjaganya.
///
/// Aturannya: **role menjawab "dia siapa", permission menjawab "dia boleh
/// apa"**. Untuk role pakai `SessionManager.instance.isOwner`. Kalau yang
/// dibutuhkan memang kemampuan, beri nama variabelnya sesuai kemampuan itu
/// (`_bolehLihatPengeluaran`), jangan `isOwner`.
void main() {
  /// Nama variabel/getter yang menyatakan IDENTITAS, bukan kemampuan.
  final namaRole = RegExp(r'^(_?)(isOwner|isCashier|isAdmin|isKasir)$');

  /// `final isOwner = ...` / `bool isOwner = ...` / `bool get _isOwner =>`
  final deklarasi = RegExp(
    r'(?:final|bool)\s+(?:get\s+)?(\w+)\s*(?:=>|=)([^;]*);',
    multiLine: true,
  );

  test('tidak ada variabel role yang diisi dari hasPermission', () {
    final pelanggar = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;

      final isi = entity.readAsStringSync();
      if (!isi.contains('hasPermission')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      final baris = isi.split('\n');

      for (final m in deklarasi.allMatches(isi)) {
        final nama = m.group(1)!;
        final nilai = m.group(2)!;
        if (!namaRole.hasMatch(nama)) continue;
        if (!nilai.contains('hasPermission')) continue;

        final nomor =
            '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        pelanggar.add('$path:$nomor  →  $nama =${baris[nomor - 1].trim()}');
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Variabel di atas bernama seperti ROLE tapi diisi dari '
          'hasPermission(). Permission bisa diberikan owner ke kasir mana pun '
          'lewat halaman Izin Akses, jadi cek semacam ini bocor: kasir yang '
          'kebetulan punya permission itu akan diperlakukan sebagai owner.\n\n'
          'Perbaikannya salah satu dari:\n'
          '  • Kalau yang dimaksud memang role  → pakai '
          'SessionManager.instance.isOwner\n'
          '  • Kalau yang dimaksud kemampuan    → ganti nama variabelnya '
          'sesuai kemampuan itu, mis. _bolehLihatPengeluaran',
    );
  });

  test('kerangka owner dipilih berdasarkan role, bukan permission', () {
    // Owner mendapat KerangkaOwner (dashboard owner, tanpa shift); semua
    // akun lain tetap di drawer kasir dengan ActiveShiftCard. Kalau pilihan
    // ini memakai permission, kasir yang diberi izin tertentu akan "menjadi
    // owner" dan kehilangan kartu shiftnya — bug lama yang sama.
    final isi = File('lib/app/app_shell.dart').readAsStringSync();
    expect(
      RegExp(r'if \(SessionManager\.instance\.isOwner\) return const KerangkaOwner\(\);')
          .hasMatch(isi),
      isTrue,
      reason: 'AppShell harus memilih KerangkaOwner dari role (isOwner).',
    );
    expect(isi.contains('hasPermission'), isTrue,
        reason: 'menu kasir tetap disaring izin — test ini membaca berkas '
            'yang benar');
  });
}
