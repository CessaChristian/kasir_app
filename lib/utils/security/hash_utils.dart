import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Security utilities for hashing and recovery code generation
class HashUtils {
  // Character set excluding confusing characters (O, I, 0, 1)
  static const _recoveryCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generate a secure random salt
  /// 
  /// [length] - Length of salt in bytes (default: 16)
  /// Returns base64-encoded salt string
  static String generateSalt({int length = 16}) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Hash a value with salt using SHA-256
  /// 
  /// [value] - The value to hash (PIN, recovery code, etc)
  /// [salt] - The salt to use
  /// Returns SHA-256 hash as hex string
  static String hashWithSalt(String value, String salt) {
    final bytes = utf8.encode(salt + value);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Verify a value against stored hash and salt
  /// 
  /// [value] - The value to verify
  /// [salt] - The salt that was used
  /// [storedHash] - The stored hash to compare against
  /// Returns true if value matches
  static bool verifyWithSalt(String value, String salt, String storedHash) {
    final computedHash = hashWithSalt(value, salt);
    return computedHash == storedHash;
  }

  /// Generate a recovery code in format XXXX-XXXX-XXXX-XXXX
  /// 
  /// Uses secure random with character set excluding confusing chars
  /// Returns formatted recovery code
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

  /// Normalize recovery code for comparison
  /// 
  /// Removes spaces, dashes, converts to uppercase
  /// [code] - The raw input recovery code
  /// Returns normalized code (16 chars, no dashes)
  static String normalizeRecoveryCode(String code) {
    return code
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .trim()
        .toUpperCase();
  }

  /// Validate recovery code format
  /// 
  /// [code] - The recovery code to validate
  /// Returns true if format is valid (16 alphanumeric chars after normalization)
  static bool isValidRecoveryCodeFormat(String code) {
    final normalized = normalizeRecoveryCode(code);
    if (normalized.length != 16) return false;
    return RegExp(r'^[A-Z0-9]+$').hasMatch(normalized);
  }

  /// Format recovery code for display (add dashes)
  /// 
  /// [code] - Normalized recovery code (16 chars)
  /// Returns formatted code XXXX-XXXX-XXXX-XXXX
  static String formatRecoveryCode(String code) {
    final normalized = normalizeRecoveryCode(code);
    if (normalized.length != 16) return code;
    
    return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}-${normalized.substring(12, 16)}';
  }
}
