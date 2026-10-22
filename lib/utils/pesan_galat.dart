import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, PostgrestException;

/// Pesan untuk galat jaringan, dipakai di mana pun koneksinya putus.
const pesanTakTersambung =
    'Tidak tersambung ke server. Periksa internet lalu coba lagi.';

/// Galat → kalimat yang bisa dibaca kasir dan owner.
///
/// Dulu halaman menampilkan galat apa adanya: "Gagal: Bad state: Permission
/// required: manage_products" atau teks mentah PostgREST. Kasir tidak tahu
/// harus berbuat apa, dan isi bagian dalam aplikasi ikut terpampang.
///
/// - Galat aturan aplikasi ([StateError], [ArgumentError]) sudah berupa
///   kalimat untuk pengguna: dipakai apa adanya.
/// - Putus koneksi atau server lambat → [pesanTakTersambung].
/// - Penolakan dari fungsi server (`raise exception`) → pesannya.
/// - Selain itu → "[awalan]. Coba lagi."; galat aslinya hanya dicatat di log.
String pesanGalat(Object e, {String awalan = 'Terjadi kesalahan'}) {
  switch (e) {
    case StateError(:final message):
      return message;
    case ArgumentError(:final message):
      return '$message';
    case SocketException() ||
        TimeoutException() ||
        HandshakeException() ||
        ClientException() ||
        AuthRetryableFetchException():
      return pesanTakTersambung;
    case PostgrestException(:final code, :final message)
        when const {'28000', '42501', 'P0001'}.contains(code):
      return _kalimat(message);
  }
  debugPrint('[galat] $awalan: $e');
  return '$awalan. Coba lagi.';
}

/// "perangkat ini tidak berhak" → "Perangkat ini tidak berhak."
String _kalimat(String teks) {
  final t = teks.trim();
  if (t.isEmpty) return t;
  final awal = t[0].toUpperCase() + t.substring(1);
  return awal.endsWith('.') ? awal : '$awal.';
}
