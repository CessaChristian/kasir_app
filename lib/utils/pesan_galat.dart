import 'dart:async';
import 'dart:io';

// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, PostgrestException;

import '../shared/services/catatan_error.dart';

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
    'Data di HP ini rusak. Tutup lalu buka lagi aplikasi untuk memperbaikinya. '
    'Kalau masih muncul, hubungi owner.';

/// Database HP ini gagal dibaca atau ditulis, tapi berkasnya belum tentu
/// rusak — pemeriksaan saat aplikasi dibuka tidak menemukan apa pun untuk
/// galat seperti ini, jadi "buka lagi untuk memperbaikinya" tidak pernah
/// terjadi (audit 6 Nov nomor 44).
const pesanDatabaseGagalBaca =
    'Data di HP ini gagal dibaca. Tutup lalu buka lagi aplikasinya. '
    'Kalau masih muncul, hubungi owner.';

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
  if (database != null) {
    // Memori penuh bukan kesalahan aplikasi; sisanya dicatat, dan memicu
    // pemeriksaan berkas database (PenjagaDatabase).
    if (database != pesanMemoriPenuh) {
      CatatanError.instance.catat(e, StackTrace.current, sumber: 'tertangkap');
    }
    return database;
  }
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
  // Galat yang tidak dikenali = kemungkinan bug: dilaporkan ke server.
  CatatanError.instance.catat(
    e,
    e is Error ? e.stackTrace : StackTrace.current,
    sumber: 'tertangkap',
  );
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
  // Hanya yang juga ditemukan pemeriksaan berkas saat aplikasi dibuka
  // (periksaBerkasDatabase): tabel inti hilang, berkas rusak, bukan database.
  const rusak = ['no such table', 'malformed', 'not a database'];
  if (rusak.any(isi.contains)) return pesanDatabaseRusak;
  const gagalBaca = [
    'no such column',
    'disk i/o error',
    'unable to open database',
  ];
  return gagalBaca.any(isi.contains) ? pesanDatabaseGagalBaca : null;
}

/// Galat dari database HP ini yang menandakan berkasnya mungkin rusak atau
/// tidak terbaca — pemicu pemeriksaan berkas di tengah pemakaian.
bool galatDatabase(Object e) {
  final pesan = _pesanDatabase(e);
  return pesan == pesanDatabaseRusak || pesan == pesanDatabaseGagalBaca;
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
