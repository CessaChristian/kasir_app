import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Utility class untuk operasi cryptographic.
///
/// PIN dihash dengan PBKDF2-HMAC-SHA256 (120.000 iterations) untuk
/// melindungi dari brute-force offline jika database bocor.
///
/// Format hash baru: `pbkdf2:<iterations>:<base64-hash>`
/// Hash lama (SHA-256 single-pass) DITOLAK sejak audit 6 Nov nomor 3.
class CryptoUtils {
  // PBKDF2 parameters
  static const int _pbkdf2Iterations = 120000;
  static const int _pbkdf2KeyLength = 32; // 256 bits
  static const String _pbkdf2Prefix = 'pbkdf2:';

  /// Batas jumlah putaran yang diterima dari hash tersimpan.
  static const int putaranMinimum = 100000;
  static const int putaranMaksimum = 1000000;

  /// Panjang PIN — satu-satunya sumber kebenaran untuk seluruh aplikasi.
  /// Halaman login, onboarding, kelola kasir, dan reset PIN semuanya
  /// mengacu ke sini.
  static const int pinLength = 6;

  /// Generate a random salt for password hashing.
  ///
  /// [length] - Length of the salt in bytes (default: 32)
  /// Returns a base64url-encoded salt string.
  static String generateSalt({int length = 32}) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Hash PIN dengan PBKDF2-HMAC-SHA256.
  ///
  /// Returns format: `pbkdf2:<iterations>:<base64-hash>`
  static String hashPin(String pin, String salt) {
    final derived = _pbkdf2(
      utf8.encode(pin),
      utf8.encode(salt),
      _pbkdf2Iterations,
      _pbkdf2KeyLength,
    );
    return '$_pbkdf2Prefix$_pbkdf2Iterations:${base64.encode(derived)}';
  }

  /// Verify PIN — hanya format PBKDF2.
  ///
  /// Menggunakan constant-time comparison untuk mencegah timing attack.
  static bool verifyPin(String pin, String salt, String storedHash) {
    if (storedHash.startsWith(_pbkdf2Prefix)) {
      return _verifyPbkdf2(pin, salt, storedHash);
    }
    // Format lama (SHA-256 sekali) DITOLAK (audit 6 Nov nomor 3): bisa
    // dibongkar dalam hitungan detik. Semua akun sudah berformat baru.
    return false;
  }

  /// [hashPin] di isolate lain. PBKDF2 120.000 putaran makan ratusan
  /// milidetik; di isolate utama ia menahan gambar layar — tombol "Memeriksa…"
  /// baru tampil setelah semuanya selesai, dan HP terlihat macet.
  static Future<String> hashPinDiLatar(String pin, String salt) =>
      Isolate.run(() => hashPin(pin, salt));

  /// [verifyPin] di isolate lain — lihat [hashPinDiLatar].
  static Future<bool> verifyPinDiLatar(
    String pin,
    String salt,
    String storedHash,
  ) =>
      Isolate.run(() => verifyPin(pin, salt, storedHash));

  /// True jika hash pakai format lama dan perlu di-rehash.
  ///
  /// Dipanggil di auth_repository setelah login berhasil untuk
  /// migrasi transparan ke PBKDF2.
  static bool needsRehash(String storedHash) {
    return !storedHash.startsWith(_pbkdf2Prefix);
  }

  /// Validate PIN format — WAJIB tepat [pinLength] digit.
  ///
  /// Dulu 4-6 digit, dan itu melahirkan bug serius: halaman login membatasi
  /// ketikan di 4 karakter, sementara pembuatan akun mengizinkan sampai 6.
  /// Akun ber-PIN 5 atau 6 digit tidak akan pernah bisa masuk — keyboardnya
  /// berhenti menerima sebelum PIN selesai diketik, hash tidak pernah cocok,
  /// dan tidak ada pesan error yang menjelaskan sebabnya.
  static bool isValidPinFormat(String pin) {
    if (pin.length != pinLength) return false;
    return RegExp(r'^\d+$').hasMatch(pin);
  }

  // ============================================================
  // Private implementations
  // ============================================================

  static bool _verifyPbkdf2(String pin, String salt, String storedHash) {
    final body = storedHash.substring(_pbkdf2Prefix.length);
    final colonIdx = body.indexOf(':');
    if (colonIdx <= 0) return false;

    final iterations = int.tryParse(body.substring(0, colonIdx));
    // Nilainya ikut sinkron dari server, jadi tidak dipercaya mentah: angka
    // raksasa membuat pemeriksaan macet berjam-jam.
    if (iterations == null ||
        iterations < putaranMinimum ||
        iterations > putaranMaksimum) {
      return false;
    }

    final Uint8List expected;
    try {
      expected = base64.decode(body.substring(colonIdx + 1));
    } catch (_) {
      return false;
    }
    // Hash kosong dulu dianggap cocok dengan PIN apa pun: "kosong sama dengan
    // kosong" (audit 6 Nov nomor 5).
    if (expected.length != _pbkdf2KeyLength) return false;

    final computed = _pbkdf2(
      utf8.encode(pin),
      utf8.encode(salt),
      iterations,
      expected.length,
    );
    return _constantTimeEquals(computed, expected);
  }

  /// PBKDF2-HMAC-SHA256 (RFC 2898).
  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    const hashSize = 32; // SHA-256 output size
    final blockCount = (keyLength + hashSize - 1) ~/ hashSize;
    final result = Uint8List(blockCount * hashSize);

    final blockIndexBytes = ByteData(4);
    final saltedBlock = Uint8List(salt.length + 4);
    saltedBlock.setRange(0, salt.length, salt);

    for (int blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      blockIndexBytes.setUint32(0, blockIndex, Endian.big);
      saltedBlock.setRange(
          salt.length, salt.length + 4, blockIndexBytes.buffer.asUint8List());

      var u = Uint8List.fromList(hmac.convert(saltedBlock).bytes);
      final f = Uint8List.fromList(u);

      for (int i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int j = 0; j < f.length; j++) {
          f[j] ^= u[j];
        }
      }

      result.setRange((blockIndex - 1) * hashSize, blockIndex * hashSize, f);
    }

    return result.sublist(0, keyLength);
  }

  /// Constant-time byte comparison — mencegah timing attack.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

}
