import 'dart:async';
import 'dart:io';

// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, PostgrestException;

/// Pesan untuk galat jaringan, dipakai di mana pun koneksinya putus.
const pesanTakTersambung =
    'Tidak tersambung ke server. Periksa internet lalu coba lagi.';

/// Server menolak lewat aturan aksesnya sendiri, bukan lewat fungsi kita.
const pesanAksesDitolak =
    'Server menolak akses perangkat ini. Minta owner memeriksa Daftar Perangkat.';

/// Database di HP ini tidak bisa dibaca. Install ulang memang memperbaikinya,
/// tapi menghapus transaksi yang belum terkirim dan HP harus didaftarkan lagi,
/// jadi owner perlu tahu lebih dulu.
const pesanDatabaseRusak =
    'Data di HP ini rusak. Tutup lalu buka lagi aplikasi. Kalau masih muncul, '
    'hubungi owner sebelum install ulang, karena transaksi yang belum terkirim '
    'bisa hilang.';

/// Memori HP habis saat menulis database.
const pesanMemoriPenuh = 'Memori HP penuh. Kosongkan dulu lalu coba lagi.';

/// Galat → kalimat yang bisa dibaca kasir dan owner.
///
/// Dulu halaman menampilkan galat apa adanya: "Gagal: Bad state: Permission
/// required: manage_products" atau teks mentah PostgREST. Kasir tidak tahu
/// harus berbuat apa, dan isi bagian dalam aplikasi ikut terpampang.
///
/// - Galat aturan aplikasi ([StateError], [ArgumentError]) sudah berupa
///   kalimat untuk pengguna: dipakai apa adanya.
/// - Putus koneksi atau server lambat → [pesanTakTersambung].
/// - Penolakan dari fungsi server (`raise exception`) → pesannya. Penolakan
///   bawaan Postgres berbahasa Inggris dan menyebut nama tabel, jadi diganti
///   [pesanAksesDitolak].
/// - Selain itu → "[awalan]. Coba lagi."; galat aslinya hanya dicatat di log.
String pesanGalat(Object e, {String awalan = 'Terjadi kesalahan'}) {
  if (galatTakTersambung(e)) return pesanTakTersambung;
  final database = _pesanDatabase(e);
  if (database != null) return database;
  switch (e) {
    case StateError(:final message) when !_galatDart.contains(message):
      return message;
    case ArgumentError(:final message):
      return '$message';
    case PostgrestException(:final code, :final message)
        when const {'28000', '42501', 'P0001'}.contains(code):
      return _penolakanBawaan.hasMatch(message)
          ? pesanAksesDitolak
          : _kalimat(message);
  }
  debugPrint('[galat] $awalan: $e');
  return '$awalan. Coba lagi.';
}

/// Pesan [StateError] dari Dart sendiri (`.single`, `.first`), bukan kalimat
/// aturan aplikasi.
const _galatDart = {'No element', 'Too many elements'};

/// Pesan bawaan Postgres untuk kode 28000/42501.
final _penolakanBawaan = RegExp(
  r'permission denied|row-level security|must be owner|role ".*" does not exist',
  caseSensitive: false,
);

/// Kalimat untuk galat SQLite, atau null kalau bukan salah satu yang dikenali.
///
/// Database aplikasi berjalan di isolate terpisah, jadi galatnya sampai
/// terbungkus [DriftRemoteException]. Sengaja bukan semua galat SQLite:
/// penolakan biasa seperti aturan kunci tidak berarti filenya rusak.
String? _pesanDatabase(Object e) {
  final asli = e is DriftRemoteException ? e.remoteCause : e;
  if (e is! DriftRemoteException && asli is! SqliteException) return null;
  final isi = '$asli'.toLowerCase();
  if (isi.contains('disk is full')) return pesanMemoriPenuh;
  const rusak = [
    'no such table',
    'no such column',
    'malformed',
    'not a database',
    'disk i/o error',
    'unable to open database',
  ];
  return rusak.any(isi.contains) ? pesanDatabaseRusak : null;
}

/// Putus koneksi atau server tidak menjawab — bukan penolakan dari server.
bool galatTakTersambung(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is ClientException ||
    e is AuthRetryableFetchException;

/// "perangkat ini tidak berhak" → "Perangkat ini tidak berhak."
String _kalimat(String teks) {
  final t = teks.trim();
  if (t.isEmpty) return t;
  final awal = t[0].toUpperCase() + t.substring(1);
  return awal.endsWith('.') ? awal : '$awal.';
}
