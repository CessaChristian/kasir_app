import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mengunci perilaku saat daftar perangkat BELUM dibuat di server.
///
/// ── KENAPA INI PENTING ──
///
/// Tabel dan fungsinya dibuat lewat berkas SQL yang dijalankan pemilik dari
/// dashboard. Selalu ada jeda antara aplikasinya diperbarui dan SQL-nya
/// dijalankan — dan selama jeda itu aplikasi TIDAK BOLEH rusak.
///
/// Tanpa penggolongan ini, HP yang baru diperbarui akan gagal mendaftar dan
/// gagal menyinkron hanya karena menanyakan sesuatu yang memang belum ada.
void main() {
  PostgrestException galat(String kode, [String pesan = '']) =>
      PostgrestException(message: pesan, code: kode);

  group('dikenali sebagai "belum disiapkan"', () {
    test('fungsi tidak ditemukan lewat PostgREST', () {
      expect(PerangkatRepository.belumDisiapkan(galat('PGRST202')), isTrue);
    });

    test('tabel tidak ada', () {
      expect(PerangkatRepository.belumDisiapkan(galat('42P01')), isTrue);
    });

    test('fungsi tidak ada menurut Postgres', () {
      expect(PerangkatRepository.belumDisiapkan(galat('42883')), isTrue);
    });

    test('dikenali dari kalimatnya kalau kodenya tidak terbaca', () {
      expect(
        PerangkatRepository.belumDisiapkan(
            galat('', 'relation "public.perangkat" does not exist')),
        isTrue,
      );
    });
  });

  group('TIDAK boleh dianggap "belum disiapkan"', () {
    test('kunci pemasangan salah', () {
      // Ini penolakan yang sesungguhnya. Menelannya berarti perangkat
      // terdaftar tanpa kunci yang benar.
      expect(PerangkatRepository.belumDisiapkan(galat('28000')), isFalse);
    });

    test('ditolak aturan tabel', () {
      expect(PerangkatRepository.belumDisiapkan(galat('42501')), isFalse);
    });

    test('galat biasa di luar Postgrest', () {
      expect(PerangkatRepository.belumDisiapkan(StateError('x')), isFalse);
    });
  });
}
