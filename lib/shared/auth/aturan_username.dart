import 'package:flutter/services.dart';

/// Aturan username — satu tempat untuk semua jalur: buat kasir, ganti nama
/// kasir, dan buat akun owner (keputusan owner 2026-10-28).
///
/// Hanya huruf kecil `a–z`, angka, titik, dan garis bawah, 3–20 karakter.
/// Dulu `Sari` dan `sari` dianggap dua akun berbeda, dan huruf tak terlihat
/// atau huruf Cyrillic yang mirip Latin (`а` vs `a`) lolos, sehingga dua akun
/// bisa terlihat sama persis di layar.
const panjangUsernameMin = 3;
const panjangUsernameMaks = 20;

final _polaUsername = RegExp(r'^[a-z0-9._]+$');
final _bukanHurufUsername = RegExp(r'[^a-z0-9._]');

/// Galat aturan username, atau null kalau sah.
String? periksaUsername(String nama) {
  final n = nama.trim();
  if (n.isEmpty) return 'Username wajib diisi';
  if (n.length < panjangUsernameMin || n.length > panjangUsernameMaks) {
    return 'Username harus $panjangUsernameMin–$panjangUsernameMaks karakter';
  }
  if (!_polaUsername.hasMatch(n)) {
    return 'Username hanya boleh huruf kecil, angka, titik, dan garis bawah';
  }
  return null;
}

/// Bentuk pembanding username: tanpa spasi di ujung, huruf kecil. Dipakai
/// saat memeriksa nama kembar, supaya akun lama yang terlanjur memuat huruf
/// besar tetap dianggap kembar. Login TIDAK memakainya — harus persis.
String kunciUsername(String nama) => nama.trim().toLowerCase();

/// Isian username: huruf besar langsung jadi kecil (walau Caps Lock
/// menyala), karakter lain dibuang, paling panjang [panjangUsernameMaks].
class UsernameInputFormatter extends TextInputFormatter {
  const UsernameInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String bersihkan(String t) =>
        t.toLowerCase().replaceAll(_bukanHurufUsername, '');

    var teks = bersihkan(newValue.text);
    if (teks.length > panjangUsernameMaks) {
      teks = teks.substring(0, panjangUsernameMaks);
    }
    final kursor = newValue.selection.end.clamp(0, newValue.text.length);
    final posisi = bersihkan(
      newValue.text.substring(0, kursor),
    ).length.clamp(0, teks.length);
    return TextEditingValue(
      text: teks,
      selection: TextSelection.collapsed(offset: posisi),
    );
  }
}
