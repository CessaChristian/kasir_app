import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Utility class untuk operasi cryptographic.
///
/// PIN dihash dengan PBKDF2-HMAC-SHA256 (120.000 iterations) untuk
/// melindungi dari brute-force offline jika database bocor.
///
/// Format hash baru: `pbkdf2:<iterations>:<base64-hash>`
/// Hash lama (SHA-256 single-pass) tetap bisa diverifikasi untuk
/// kompatibilitas, dan akan otomatis di-rehash saat user login.
class CryptoUtils {
  // PBKDF2 parameters
  static const int _pbkdf2Iterations = 120000;
  static const int _pbkdf2KeyLength = 32; // 256 bits
  static const String _pbkdf2Prefix = 'pbkdf2:';

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

  /// Verify PIN — auto-detect format (PBKDF2 baru atau SHA-256 lama).
  ///
  /// Menggunakan constant-time comparison untuk mencegah timing attack.
  static bool verifyPin(String pin, String salt, String storedHash) {
    if (storedHash.startsWith(_pbkdf2Prefix)) {
      return _verifyPbkdf2(pin, salt, storedHash);
    }
    // Legacy SHA-256 — tetap diverifikasi agar user lama bisa login,
    // lalu auth_repository akan re-hash ke PBKDF2 setelah berhasil.
    return _verifyLegacySha256(pin, salt, storedHash);
  }

  /// True jika hash pakai format lama dan perlu di-rehash.
  ///
  /// Dipanggil di auth_repository setelah login berhasil untuk
  /// migrasi transparan ke PBKDF2.
  static bool needsRehash(String storedHash) {
    return !storedHash.startsWith(_pbkdf2Prefix);
  }

  /// Validate PIN format (4-6 digits).
  static bool isValidPinFormat(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
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
    if (iterations == null || iterations <= 0) return false;

    final Uint8List expected;
    try {
      expected = base64.decode(body.substring(colonIdx + 1));
    } catch (_) {
      return false;
    }

    final computed = _pbkdf2(
      utf8.encode(pin),
      utf8.encode(salt),
      iterations,
      expected.length,
    );
    return _constantTimeEquals(computed, expected);
  }

  static bool _verifyLegacySha256(
      String pin, String salt, String storedHash) {
    final bytes = utf8.encode(pin + salt);
    final computed = sha256.convert(bytes).toString();
    return _constantTimeStringEquals(computed, storedHash);
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

  /// Constant-time string comparison — mencegah timing attack.
  static bool _constantTimeStringEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
