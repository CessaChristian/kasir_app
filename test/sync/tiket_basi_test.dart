import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mengunci beda antara "ADA tiket" dan "tiket MASIH HIDUP".
///
/// ── MASALAH YANG DIKUNCI ──
///
/// `pastikanTerhubung` dulu cukup memeriksa `currentSession != null` — ada
/// tiket atau tidak, bukan tiketnya masih berlaku atau tidak. Akibatnya HP
/// yang didiamkan semalam membuka pagi harinya, menyinkron dengan tiket yang
/// sudah mati, ditolak server, lalu menampilkan "periksa koneksi" — padahal
/// internetnya sehat dan yang perlu dilakukan cuma menukar tiket.
///
/// Masa berlaku dibaca dari DALAM tiketnya sendiri (gotrue men-decode klaim
/// `exp`), bukan dari angka yang tersimpan terpisah.
Session _tiket({required Duration sisaUmur}) {
  String b64(Map<String, dynamic> m) => base64Url
      .encode(utf8.encode(jsonEncode(m)))
      .replaceAll('=', ''); // JWT tidak memakai padding

  final exp = DateTime.now().add(sisaUmur).millisecondsSinceEpoch ~/ 1000;
  final token = '${b64({'alg': 'HS256'})}.${b64({'exp': exp})}.tandatangan';

  return Session(
    accessToken: token,
    tokenType: 'bearer',
    user: const User(
      id: '00000000-0000-0000-0000-000000000001',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );
}

void main() {
  group('sesiMasihBisaDipakai', () {
    test('tidak ada tiket sama sekali -> tidak bisa dipakai', () {
      expect(SupabaseService.sesiMasihBisaDipakai(null), isFalse);
    });

    test('tiket masih lama umurnya -> bisa dipakai', () {
      expect(
        SupabaseService.sesiMasihBisaDipakai(
            _tiket(sisaUmur: const Duration(minutes: 30))),
        isTrue,
      );
    });

    test('tiket sudah mati -> TIDAK bisa dipakai walau barangnya ada', () {
      expect(
        SupabaseService.sesiMasihBisaDipakai(
            _tiket(sisaUmur: const Duration(minutes: -5))),
        isFalse,
        reason: 'inilah keadaan HP yang baru dibuka setelah didiamkan semalam',
      );
    });

    test('tiket yang akan mati dalam hitungan detik dianggap mati', () {
      // gotrue memberi margin 10 detik supaya permintaan yang sedang jalan
      // tidak kedaluwarsa di tengah jalan.
      expect(
        SupabaseService.sesiMasihBisaDipakai(
            _tiket(sisaUmur: const Duration(seconds: 3))),
        isFalse,
        reason: 'menukar sedikit lebih awal jauh lebih murah daripada satu '
            'putaran sinkron yang gagal di tengah',
      );
    });
  });
}
