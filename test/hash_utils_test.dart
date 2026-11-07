import 'dart:async';
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

  group('hash tersimpan yang tidak dipercaya (audit 6 Nov nomor 3 & 5)', () {
    final salt = HashUtils.generateSalt();

    test('format lama SHA-256 DITOLAK walau isinya benar', () {
      expect(HashUtils.verifyWithSalt('ABCDEFGHJKLMNPQR', salt, _legacyRecoveryHash('ABCDEFGHJKLMNPQR', salt)), isFalse);
    });

    test('bagian hash kosong atau kepotong tidak menerima apa pun', () {
      for (final h in ['pbkdf2:120000:', 'pbkdf2:1:', 'pbkdf2:120000:AAAA']) {
        expect(HashUtils.verifyWithSalt('ABCDEFGHJKLMNPQR', salt, h), isFalse, reason: h);
        expect(HashUtils.verifyWithSalt('', salt, h), isFalse, reason: h);
      }
    });

    test('jumlah putaran di luar batas ditolak tanpa dihitung', () {
      final benar = HashUtils.hashWithSalt('ABCDEFGHJKLMNPQR', salt);
      final isi = benar.split(':').last;
      for (final n in [0, 1, 99999, 1000001, 2000000000]) {
        expect(HashUtils.verifyWithSalt('ABCDEFGHJKLMNPQR', salt, 'pbkdf2:$n:$isi'), isFalse,
            reason: '$n');
      }
      expect(HashUtils.verifyWithSalt('ABCDEFGHJKLMNPQR', salt, benar), isTrue);
    });
  });
  group('di latar (isolate lain)', () {
    test('hasilnya sama dan layar tetap hidup', () async {
      final salt = HashUtils.generateSalt();
      var detak = 0;
      final jam = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => detak++,
      );
      final hash = await HashUtils.hashWithSaltDiLatar('ABCD2345', salt);
      final saatBuat = detak;
      detak = 0;
      final cocok =
          await HashUtils.verifyWithSaltDiLatar('ABCD2345', salt, hash);
      jam.cancel();
      expect(hash, HashUtils.hashWithSalt('ABCD2345', salt));
      expect(cocok, isTrue);
      expect(
        await HashUtils.verifyWithSaltDiLatar('ABCD2346', salt, hash),
        isFalse,
      );
      expect(saatBuat, greaterThanOrEqualTo(5));
      expect(detak, greaterThanOrEqualTo(5));
    });
  });
}
