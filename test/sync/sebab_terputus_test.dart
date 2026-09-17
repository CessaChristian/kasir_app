import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/supabase_service.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/shared/widgets/alasan_terputus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mengunci pembedaan "internet mati" dari "perangkat ditolak server".
///
/// ── MASALAH YANG DIKUNCI ──
///
/// Dulu setiap kegagalan menyambung berakhir dengan pesan yang sama: "periksa
/// koneksi". Untuk HP yang password perangkatnya sudah diganti pemilik, pesan
/// itu mengirim kasir memburu masalah yang tidak ada — mencabut router,
/// pindah ke kuota, menelepon provider — sementara penyebab sebenarnya tidak
/// akan pernah pulih dengan cara apa pun dari sisi HP.
///
/// Informasi pembedanya sebenarnya selalu ada: gotrue melempar jenis galat
/// yang berbeda untuk keduanya. Ia hanya dibuang oleh `catch (_)`.
void main() {
  group('golongkanGagalMasuk', () {
    test('jaringan putus -> jaringan', () {
      // Bentuk persis yang dilempar gotrue saat permintaan HTTP gagal total
      // (fetch.dart: `catch (e) { throw AuthRetryableFetchException(...) }`).
      expect(
        golongkanGagalMasuk(
          AuthRetryableFetchException(
            message: 'ClientException with SocketException: Failed host lookup',
          ),
        ),
        SebabTerputus.jaringan,
      );
    });

    test('server gangguan (5xx) -> jaringan, BUKAN ditolak', () {
      // Server sedang sakit bukan berarti perangkat ini dicabut. Menyebutnya
      // dicabut membuat kasir menelepon pemilik untuk hal yang pulih sendiri.
      expect(
        golongkanGagalMasuk(
          AuthRetryableFetchException(
            message: 'bad gateway',
            statusCode: '502',
          ),
        ),
        SebabTerputus.jaringan,
      );
    });

    for (final kode in const [
      'invalid_credentials', // password diganti pemilik
      'user_not_found', //      akun perangkat dihapus
      'user_banned', //         akun perangkat diblokir
      'email_not_confirmed', // akun perangkat belum selesai disiapkan
    ]) {
      test('server menolak ($kode) -> ditolak', () {
        expect(
          golongkanGagalMasuk(
            AuthApiException('ditolak', statusCode: '400', code: kode),
          ),
          SebabTerputus.ditolak,
        );
      });
    }

    test(
      'dibatasi karena terlalu sering mencoba -> jaringan, BUKAN ditolak',
      () {
        // 4xx tapi bukan penolakan kredensial. Akan pulih sendiri dalam
        // beberapa menit — tidak boleh dilaporkan sebagai pencabutan.
        expect(
          golongkanGagalMasuk(
            AuthApiException(
              'tunggu',
              statusCode: '429',
              code: 'over_request_rate_limit',
            ),
          ),
          SebabTerputus.jaringan,
        );
      },
    );

    test(
      '4xx tanpa kode -> jaringan (hanya yakin kalau server bilang jelas)',
      () {
        // Menuduh "dicabut" tanpa kepastian lebih mahal daripada diam: pesan
        // yang pernah keliru tidak akan dipercaya lagi saat benar.
        expect(
          golongkanGagalMasuk(AuthApiException('?', statusCode: '400')),
          SebabTerputus.jaringan,
        );
      },
    );

    test('galat lain di luar gotrue -> jaringan', () {
      expect(
        golongkanGagalMasuk(const SocketException('putus')),
        SebabTerputus.jaringan,
      );
      expect(golongkanGagalMasuk(StateError('aneh')), SebabTerputus.jaringan);
    });
  });

  group('HasilSync membawa sebabnya', () {
    test('denganGambar tidak menjatuhkan sebabTerputus', () {
      const h = HasilSync(error: 'x', sebabTerputus: SebabTerputus.ditolak);
      expect(h.denganGambar().sebabTerputus, SebabTerputus.ditolak);
    });
  });

  group('alasanTakPulihSendiri — kalimat untuk pengguna', () {
    test('ditolak: TIDAK menyuruh memeriksa koneksi', () {
      final a = alasanTakPulihSendiri(SebabTerputus.ditolak)!;
      expect(a, contains('tidak dikenali server'));
      expect(a.toLowerCase(), isNot(contains('koneksi')));
      expect(a.toLowerCase(), isNot(contains('internet')));
    });

    test('belum disiapkan: punya kalimat sendiri', () {
      expect(
        alasanTakPulihSendiri(SebabTerputus.belumDisiapkan),
        contains('belum disiapkan'),
      );
    });

    test('jaringan dan tanpa sebab: null — pakai pesan koneksi yang biasa', () {
      expect(alasanTakPulihSendiri(SebabTerputus.jaringan), isNull);
      expect(alasanTakPulihSendiri(null), isNull);
    });
  });
}
