import 'dart:async';
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

  group('hash tersimpan yang tidak dipercaya (audit 6 Nov nomor 3 & 5)', () {
    final salt = CryptoUtils.generateSalt();

    test('format lama SHA-256 DITOLAK walau isinya benar', () {
      expect(CryptoUtils.verifyPin('123456', salt, _legacyHash('123456', salt)), isFalse);
    });

    test('bagian hash kosong atau kepotong tidak menerima apa pun', () {
      for (final h in ['pbkdf2:120000:', 'pbkdf2:1:', 'pbkdf2:120000:AAAA']) {
        expect(CryptoUtils.verifyPin('123456', salt, h), isFalse, reason: h);
        expect(CryptoUtils.verifyPin('', salt, h), isFalse, reason: h);
      }
    });

    test('jumlah putaran di luar batas ditolak tanpa dihitung', () {
      final benar = CryptoUtils.hashPin('123456', salt);
      final isi = benar.split(':').last;
      for (final n in [0, 1, 99999, 1000001, 2000000000]) {
        expect(CryptoUtils.verifyPin('123456', salt, 'pbkdf2:$n:$isi'), isFalse,
            reason: '$n');
      }
      expect(CryptoUtils.verifyPin('123456', salt, benar), isTrue);
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
  group('di latar (isolate lain)', () {
    test('hasilnya sama persis dengan versi biasa', () async {
      final salt = CryptoUtils.generateSalt();
      final hash = await CryptoUtils.hashPinDiLatar('123456', salt);
      expect(hash, CryptoUtils.hashPin('123456', salt),
          reason: 'PIN lama harus tetap bisa dipakai masuk');
      expect(await CryptoUtils.verifyPinDiLatar('123456', salt, hash), isTrue);
      expect(await CryptoUtils.verifyPinDiLatar('999999', salt, hash), isFalse);
    });

    test('layar tetap hidup selama PIN diperiksa dan dibuat', () async {
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('123456', salt);
      var detak = 0;
      final jam = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => detak++,
      );
      await CryptoUtils.verifyPinDiLatar('123456', salt, hash);
      final saatPeriksa = detak;
      detak = 0;
      await CryptoUtils.hashPinDiLatar('123456', salt);
      jam.cancel();
      expect(saatPeriksa, greaterThanOrEqualTo(5),
          reason: 'PBKDF2 di isolate utama menahan semua kerja lain — '
              'termasuk menggambar tombol "Memeriksa…"');
      expect(detak, greaterThanOrEqualTo(5));
    });
  });
}
