import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Utility class for cryptographic operations
class CryptoUtils {
  /// Generate a random salt for password hashing
  /// 
  /// [length] - Length of the salt in bytes (default: 32)
  /// Returns a base64url-encoded salt string
  static String generateSalt({int length = 32}) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Hash a PIN with a salt using SHA-256
  /// 
  /// [pin] - The PIN to hash (4-6 digits as string)
  /// [salt] - The salt to use
  /// Returns the SHA-256 hash as a hex string
  static String hashPin(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Verify a PIN against a stored hash
  /// 
  /// [pin] - The PIN to verify
  /// [salt] - The salt that was used
  /// [storedHash] - The stored hash to compare against
  /// Returns true if PIN matches, false otherwise
  static bool verifyPin(String pin, String salt, String storedHash) {
    final computedHash = hashPin(pin, salt);
    return computedHash == storedHash;
  }

  /// Validate PIN format (4-6 digits)
  /// 
  /// [pin] - The PIN to validate
  /// Returns true if valid format, false otherwise
  static bool isValidPinFormat(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
    return RegExp(r'^\d+$').hasMatch(pin);
  }
}
