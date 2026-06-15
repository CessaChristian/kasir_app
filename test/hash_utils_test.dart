import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/security/hash_utils.dart';

// Helper: hash format lama pakai (salt + value), bukan (value + salt)
String _legacyRecoveryHash(String code, String salt) {
  return sha256.convert(utf8.encode(salt + code)).toString();
}

void main() {
  group('HashUtils PBKDF2', () {
    test('hash dan verify recovery code yang valid', () {
      final salt = HashUtils.generateSalt();
      const code = 'ABCD-EFGH-JKLM-NPQR';
      final normalized = HashUtils.normalizeRecoveryCode(code);
      final hash = HashUtils.hashWithSalt(normalized, salt);

      expect(hash, startsWith('pbkdf2:120000:'));
      expect(HashUtils.verifyWithSalt(normalized, salt, hash), isTrue);
    });

    test('reject recovery code yang salah', () {
      final salt = HashUtils.generateSalt();
      final hash = HashUtils.hashWithSalt('ABCDEFGHIJKLMNOP', salt);

      expect(HashUtils.verifyWithSalt('XXXXXXXXXXXXXXXX', salt, hash), isFalse);
    });

    test('salt unik', () {
      final salts = List.generate(50, (_) => HashUtils.generateSalt());
      expect(salts.toSet().length, 50);
    });

    test('recovery code format validation', () {
      expect(HashUtils.isValidRecoveryCodeFormat('ABCD-EFGH-JKLM-NPQR'), isTrue);
      expect(HashUtils.isValidRecoveryCodeFormat('abcd-efgh-jklm-npqr'), isTrue);
      expect(HashUtils.isValidRecoveryCodeFormat('ABCD-EFGH-JKLM'), isFalse);
      expect(HashUtils.isValidRecoveryCodeFormat('abcd1234'), isFalse);
    });

    test('generateRecoveryCode format XXXX-XXXX-XXXX-XXXX', () {
      for (int i = 0; i < 10; i++) {
        final code = HashUtils.generateRecoveryCode();
        expect(code.length, 19); // 16 chars + 3 dashes
        expect(code[4], '-');
        expect(code[9], '-');
        expect(code[14], '-');
        expect(HashUtils.isValidRecoveryCodeFormat(code), isTrue);
      }
    });

    test('character set tidak mengandung O, I, 0, 1 (ambiguity)', () {
      for (int i = 0; i < 100; i++) {
        final code = HashUtils.generateRecoveryCode();
        final normalized = HashUtils.normalizeRecoveryCode(code);
        expect(normalized.contains('O'), isFalse);
        expect(normalized.contains('I'), isFalse);
        expect(normalized.contains('0'), isFalse);
        expect(normalized.contains('1'), isFalse);
      }
    });
  });

  group('Backward compatibility — SHA-256 legacy', () {
    test('verify recovery hash format lama (SHA-256) → match', () {
      const salt = 'recovery_salt_xyz';
      const code = 'ABCDEFGHJKLMNPQR';
      final legacyHash = _legacyRecoveryHash(code, salt);

      expect(HashUtils.needsRehash(legacyHash), isTrue);
      expect(HashUtils.verifyWithSalt(code, salt, legacyHash), isTrue);
      expect(HashUtils.verifyWithSalt('WRONG-CODE-VALUE', salt, legacyHash),
          isFalse);
    });

    test('needsRehash true untuk legacy, false untuk PBKDF2', () {
      final salt = HashUtils.generateSalt();
      final newHash = HashUtils.hashWithSalt('ABCDEFGHJKLMNPQR', salt);
      final legacyHash = _legacyRecoveryHash('ABCDEFGHJKLMNPQR', salt);

      expect(HashUtils.needsRehash(newHash), isFalse);
      expect(HashUtils.needsRehash(legacyHash), isTrue);
    });

    test('roundtrip migration: legacy verify → rehash → new verify', () {
      const salt = 'migration_salt';
      const code = 'TESTCODE12345678';

      // 1. Punya hash legacy
      final legacyHash = _legacyRecoveryHash(code, salt);
      expect(HashUtils.verifyWithSalt(code, salt, legacyHash), isTrue);

      // 2. needsRehash → true → trigger re-hash
      expect(HashUtils.needsRehash(legacyHash), isTrue);

      // 3. Generate hash baru
      final newHash = HashUtils.hashWithSalt(code, salt);
      expect(newHash, startsWith('pbkdf2:'));

      // 4. Verify dengan hash baru
      expect(HashUtils.verifyWithSalt(code, salt, newHash), isTrue);
    });
  });
}
