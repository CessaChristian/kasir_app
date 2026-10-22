import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:kasir_app/data/app_database.dart' show ShiftSudahDitutup;
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/pesan_galat.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Galat yang tampil ke kasir/owner harus berupa kalimat yang bisa dibaca —
/// bukan "Bad state: Permission required: manage_products".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pesanGalat', () {
    test('galat aturan aplikasi dipakai apa adanya, tanpa "Bad state"', () {
      expect(pesanGalat(StateError('Keranjang masih kosong')),
          'Keranjang masih kosong');
      expect(pesanGalat(ShiftSudahDitutup()),
          startsWith('Shift ini sudah ditutup di perangkat lain.'));
      expect(pesanGalat(ArgumentError('Uang diterima kurang')),
          'Uang diterima kurang');
    });

    test('putus koneksi → satu pesan yang jelas', () {
      for (final e in <Object>[
        const SocketException('Failed host lookup'),
        TimeoutException('lama'),
        ClientException('Connection closed'),
      ]) {
        expect(pesanGalat(e), pesanTakTersambung, reason: '$e');
      }
    });

    test('penolakan fungsi server → pesannya, jadi kalimat', () {
      expect(
        pesanGalat(const PostgrestException(
            message: 'perangkat ini tidak berhak', code: '42501')),
        'Perangkat ini tidak berhak.',
      );
    });

    test('galat lain → awalan + "Coba lagi", tanpa isi mentahnya', () {
      final pesan = pesanGalat(
        const PostgrestException(
            message: 'relation "x" does not exist', code: '42P01'),
        awalan: 'Gagal menyimpan',
      );
      expect(pesan, 'Gagal menyimpan. Coba lagi.');
      expect(pesanGalat(Exception('aneh')), 'Terjadi kesalahan. Coba lagi.');
    });
  });

  group('pesan izin berbahasa Indonesia', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => SessionManager.instance.clearSession());

    test('belum masuk, bukan owner, izin kurang', () async {
      final sm = SessionManager.instance;
      await sm.clearSession();
      expect(() => sm.requireLoggedIn(),
          throwsA(predicate((e) =>
              pesanGalat(e!) == 'Sesi sudah berakhir. Silakan masuk lagi.')));

      await sm.setSession(AuthSession.create(
        userId: 'k',
        username: 'sari',
        role: 'cashier',
        shiftId: null,
        permissions: const [],
      ));
      expect(
        () => sm.requireOwner(),
        throwsA(isA<IzinDitolak>().having((e) => e.message, 'pesan',
            'Hanya owner yang boleh melakukan ini.')),
      );
      expect(
        () => sm.requirePermission('manage_products'),
        throwsA(isA<IzinDitolak>()
            .having((e) => e.kode, 'kode', 'manage_products')
            .having((e) => e.message, 'pesan',
                startsWith('Akun ini tidak punya izin'))),
      );
    });
  });

  test('halaman tidak lagi menampilkan galat mentah (\$e)', () {
    // Pola yang dulu dipakai: 'Gagal: $e', 'Terjadi kesalahan: $e', '$e'.
    // Catatan untuk log (debugPrint) boleh memuat galat mentah.
    final mentah = RegExp(r"""\$\{?e\}?['"]""");
    final pelanggar = <String>[];
    final berkas = Directory('lib/features')
        .listSync(recursive: true)
        .followedBy(Directory('lib/shared').listSync(recursive: true))
        .followedBy(Directory('lib/app').listSync(recursive: true))
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in berkas) {
      final baris = f.readAsLinesSync();
      for (var i = 0; i < baris.length; i++) {
        final b = baris[i];
        if (b.contains('debugPrint')) continue;
        if (mentah.hasMatch(b)) pelanggar.add('${f.path}:${i + 1}: ${b.trim()}');
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'pakai pesanGalat(e) dari lib/utils/pesan_galat.dart');
  });
}
