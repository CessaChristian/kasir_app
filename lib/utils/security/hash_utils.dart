import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Security utilities untuk hashing dan recovery code generation.
///
/// Recovery code di-hash dengan PBKDF2-HMAC-SHA256 (120.000 iterations).
/// Format baru: `pbkdf2:<iterations>:<base64-hash>`.
/// Hash lama (SHA-256 single-pass) masih bisa diverifikasi untuk
/// kompatibilitas dan otomatis di-rehash saat verifikasi berhasil.
class HashUtils {
  // Character set excluding confusing characters (O, I, 0, 1)
  static const _recoveryCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // PBKDF2 parameters
  static const int _pbkdf2Iterations = 120000;
  static const int _pbkdf2KeyLength = 32; // 256 bits
  static const String _pbkdf2Prefix = 'pbkdf2:';

  /// Generate a secure random salt.
  ///
  /// [length] - Length of salt in bytes (default: 16)
  /// Returns base64-encoded salt string.
  static String generateSalt({int length = 16}) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Hash value (recovery code, dll) dengan PBKDF2-HMAC-SHA256.
  ///
  /// Returns format: `pbkdf2:<iterations>:<base64-hash>`
  static String hashWithSalt(String value, String salt) {
    final derived = _pbkdf2(
      utf8.encode(value),
      utf8.encode(salt),
      _pbkdf2Iterations,
      _pbkdf2KeyLength,
    );
    return '$_pbkdf2Prefix$_pbkdf2Iterations:${base64.encode(derived)}';
  }

  /// Verify value — auto-detect format (PBKDF2 baru atau SHA-256 lama).
  ///
  /// Menggunakan constant-time comparison untuk mencegah timing attack.
  static bool verifyWithSalt(String value, String salt, String storedHash) {
    if (storedHash.startsWith(_pbkdf2Prefix)) {
      return _verifyPbkdf2(value, salt, storedHash);
    }
    // Legacy SHA-256 — tetap diverifikasi agar user lama tetap bisa pakai
    // recovery code mereka. auth_repository akan re-hash setelah berhasil.
    return _verifyLegacySha256(value, salt, storedHash);
  }

  /// True jika hash pakai format lama dan perlu di-rehash.
  static bool needsRehash(String storedHash) {
    return !storedHash.startsWith(_pbkdf2Prefix);
  }

  /// Generate a recovery code in format XXXX-XXXX-XXXX-XXXX.
  static String generateRecoveryCode() {
    final random = Random.secure();
    final code = List.generate(
      16,
      (_) => _recoveryCodeChars[random.nextInt(_recoveryCodeChars.length)],
    ).join();

    // Format as XXXX-XXXX-XXXX-XXXX
    return '${code.substring(0, 4)}-${code.substring(4, 8)}-'
        '${code.substring(8, 12)}-${code.substring(12, 16)}';
  }

  /// Normalize recovery code (remove dashes/spaces, uppercase).
  static String normalizeRecoveryCode(String code) {
    return code.replaceAll('-', '').replaceAll(' ', '').trim().toUpperCase();
  }

  /// Validate recovery code format (16 alphanumeric chars after normalization).
  static bool isValidRecoveryCodeFormat(String code) {
    final normalized = normalizeRecoveryCode(code);
    if (normalized.length != 16) return false;
    return RegExp(r'^[A-Z0-9]+$').hasMatch(normalized);
  }

  /// Format recovery code for display (add dashes).
  static String formatRecoveryCode(String code) {
    final normalized = normalizeRecoveryCode(code);
    if (normalized.length != 16) return code;

    return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}-${normalized.substring(12, 16)}';
  }

  // ============================================================
  // Private implementations
  // ============================================================

  static bool _verifyPbkdf2(String value, String salt, String storedHash) {
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
      utf8.encode(value),
      utf8.encode(salt),
      iterations,
      expected.length,
    );
    return _constantTimeEquals(computed, expected);
  }

  static bool _verifyLegacySha256(
      String value, String salt, String storedHash) {
    // CATATAN: format lama pakai (salt + value), beda dengan crypto_utils
    // yang pakai (pin + salt). Tetap dipertahankan agar hash existing match.
    final bytes = utf8.encode(salt + value);
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
    const hashSize = 32;
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

  /// Constant-time byte comparison.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Constant-time string comparison.
  static bool _constantTimeStringEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
