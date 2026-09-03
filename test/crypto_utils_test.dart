import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/crypto_utils.dart';

// Helper untuk simulasi hash format lama (sha256(pin+salt) hex)
String _legacyHash(String pin, String salt) {
  return sha256.convert(utf8.encode(pin + salt)).toString();
}

void main() {
  group('CryptoUtils PBKDF2', () {
    test('hash dan verify PIN yang valid', () {
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('123456', salt);

      expect(hash, startsWith('pbkdf2:120000:'));
      expect(CryptoUtils.verifyPin('123456', salt, hash), isTrue);
    });

    test('reject PIN yang salah', () {
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('123456', salt);

      expect(CryptoUtils.verifyPin('123457', salt, hash), isFalse);
      expect(CryptoUtils.verifyPin('999999', salt, hash), isFalse);
    });

    test('reject salt yang salah', () {
      final salt1 = CryptoUtils.generateSalt();
      final salt2 = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('123456', salt1);

      expect(CryptoUtils.verifyPin('123456', salt2, hash), isFalse);
    });

    test('salt unik setiap generate', () {
      final salts = List.generate(100, (_) => CryptoUtils.generateSalt());
      expect(salts.toSet().length, 100);
    });

    test('format PIN validation', () {
      expect(CryptoUtils.isValidPinFormat('123456'), isTrue);
      expect(CryptoUtils.isValidPinFormat('12345'), isFalse,
          reason: '5 digit ditolak — PIN wajib tepat 6');
      expect(CryptoUtils.isValidPinFormat('1234567'), isFalse,
          reason: '7 digit ditolak');
      expect(CryptoUtils.isValidPinFormat('abcdef'), isFalse,
          reason: 'huruf ditolak walau panjangnya pas');
    });
  });

  group('Backward compatibility — SHA-256 legacy', () {
    test('verify hash format lama (SHA-256 single-pass) → match', () {
      const salt = 'test_salt_abc';
      const pin = '123456';
      final legacyHash = _legacyHash(pin, salt);

      expect(CryptoUtils.needsRehash(legacyHash), isTrue);
      expect(CryptoUtils.verifyPin(pin, salt, legacyHash), isTrue);
      expect(CryptoUtils.verifyPin('999999', salt, legacyHash), isFalse);
    });

    test('needsRehash true untuk hash lama, false untuk hash baru', () {
      final salt = CryptoUtils.generateSalt();
      final newHash = CryptoUtils.hashPin('123456', salt);

      expect(CryptoUtils.needsRehash(newHash), isFalse);
      expect(
          CryptoUtils.needsRehash(
              '85f0e57c4ca39e7df45e1cf9d3aff70d0f4cfe1e1b86bbabd25d2c0a9c3a8d49'),
          isTrue);
    });

    test('roundtrip migration: legacy verify → rehash → new verify', () {
      const pin = '567890';
      const salt = 'legacy_salt_xyz';

      // 1. User punya hash legacy → verify dulu (login)
      final legacyHash = _legacyHash(pin, salt);
      expect(CryptoUtils.verifyPin(pin, salt, legacyHash), isTrue);

      // 2. needsRehash → true → trigger migration
      expect(CryptoUtils.needsRehash(legacyHash), isTrue);

      // 3. Generate hash baru dengan PBKDF2 (simulasi update DB)
      final newHash = CryptoUtils.hashPin(pin, salt);
      expect(newHash, startsWith('pbkdf2:120000:'));
      expect(CryptoUtils.needsRehash(newHash), isFalse);

      // 4. Verify dengan hash baru tetap jalan
      expect(CryptoUtils.verifyPin(pin, salt, newHash), isTrue);
    });
  });

  group('Timing attack protection', () {
    test('verifyPin pakai constant-time comparison (smoke test)', () {
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('123456', salt);

      // Tidak ada cara mudah untuk test timing langsung di unit test.
      // Yang penting: verify return bool, tidak ada short-circuit visible.
      expect(CryptoUtils.verifyPin('123456', salt, hash), isTrue);
      expect(CryptoUtils.verifyPin('999999', salt, hash), isFalse);
    });
  });
}
