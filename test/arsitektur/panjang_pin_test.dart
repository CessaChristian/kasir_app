import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/crypto_utils.dart';

/// Mengunci panjang PIN pada SATU angka untuk seluruh aplikasi.
///
/// Latar belakang — dulu ada TIGA aturan berbeda yang hidup berdampingan:
///
///   login_page          → keyboard berhenti di 4 karakter
///   onboarding          → wajib tepat 4 digit
///   kelola kasir/reset  → boleh 4 sampai 6 digit
///
/// Akibatnya siapa pun yang membuat PIN 5 atau 6 digit TIDAK AKAN PERNAH bisa
/// login: field-nya berhenti menerima sebelum PIN selesai diketik, hash tidak
/// pernah cocok, dan tidak ada pesan error yang menjelaskan sebabnya. Akun
/// terkunci permanen tanpa jejak.
///
/// Sekarang semuanya mengacu ke [CryptoUtils.pinLength].
void main() {
  test('isValidPinFormat menerima TEPAT sepanjang pinLength', () {
    final pas = '1' * CryptoUtils.pinLength;
    expect(CryptoUtils.isValidPinFormat(pas), isTrue);

    expect(CryptoUtils.isValidPinFormat('1' * (CryptoUtils.pinLength - 1)),
        isFalse,
        reason: 'kurang satu digit harus ditolak');
    expect(CryptoUtils.isValidPinFormat('1' * (CryptoUtils.pinLength + 1)),
        isFalse,
        reason: 'lebih satu digit harus ditolak');
    expect(CryptoUtils.isValidPinFormat('a' * CryptoUtils.pinLength), isFalse,
        reason: 'huruf ditolak walau panjangnya pas');
  });

  test('tidak ada angka panjang PIN yang ditulis langsung di lib/', () {
    /// Pola yang menandakan panjang PIN dipatok sendiri, bukan mengacu ke
    /// CryptoUtils.pinLength.
    final pola = <RegExp, String>{
      RegExp(r'LengthLimitingTextInputFormatter\(\s*\d+\s*\)'):
          'batas ketikan PIN dipatok angka',
      RegExp(r'maxLength:\s*\d+'): 'maxLength dipatok angka',
      RegExp(r'length\s*(?:!=|<|>)\s*[456]\b'): 'perbandingan panjang dipatok',
      RegExp(r'PIN harus [0-9]'): 'pesan menyebut angka langsung',
      RegExp(r'PIN \([0-9] digit\)'): 'label menyebut angka langsung',
    };

    /// File yang memang boleh memuat angka — bukan soal PIN.
    const diizinkan = <String, String>{
      'lib/utils/crypto_utils.dart': 'tempat pinLength didefinisikan',
      'lib/features/products/sheets/product_form_sheet.dart':
          'maxLength pada field nama/harga produk, bukan PIN',
      'lib/features/owner/pages/manage_cashiers_page.dart':
          'maxLength pada field username, bukan PIN',
    };

    final pelanggar = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      if (diizinkan.containsKey(path)) continue;

      // Komentar dibuang — dokumentasi sengaja menceritakan aturan lama.
      final isi = entity
          .readAsStringSync()
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

      for (final entri in pola.entries) {
        if (entri.key.hasMatch(isi)) {
          pelanggar.add('$path → ${entri.value}');
        }
      }
    }

    expect(
      pelanggar,
      isEmpty,
      reason: 'Panjang PIN harus SELALU mengacu ke CryptoUtils.pinLength, '
          'tidak boleh ditulis sebagai angka di tempat lain. Tiga aturan '
          'berbeda pernah hidup bersamaan dan mengunci akun secara permanen '
          'tanpa pesan error. Kalau angka di file itu memang bukan soal PIN, '
          'tambahkan ke map `diizinkan` beserta alasannya.',
    );
  });
}
