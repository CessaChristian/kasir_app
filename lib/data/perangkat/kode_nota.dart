import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penanda pendek milik perangkat ini, disisipkan ke setiap nomor nota.
///
/// ── MASALAH YANG DIPECAHKAN ──
///
/// Nomor nota dihitung dari JUMLAH transaksi hari ini di database LOKAL, lalu
/// ditambah satu. Tidak ada koordinasi antar perangkat, jadi dua HP yang
/// sama-sama sudah mencatat 10 transaksi hari ini akan sama-sama menerbitkan
/// nomor ke-11 — dua struk berbeda, nomor sama. Server pun tidak menolaknya:
/// `invoice_no` tidak punya batasan unik.
///
/// Menyisipkan penanda perangkat membuat tabrakan itu mustahil tanpa perlu
/// bertanya ke server — penting, karena nomor nota harus tetap terbit saat
/// internet mati.
///
/// ── KENAPA KUNCINYA TERPISAH DARI IDENTITAS PERANGKAT ──
///
/// Godaannya memakai id perangkat yang sudah ada di brankas. Tapi identitas
/// itu BERGANTI setiap kali perangkat didaftarkan ulang — misal sesudah
/// dicabut lalu dipulihkan. Kalau nomor nota ikut berganti, dua struk lama
/// dan baru dari HP yang sama jadi tidak bisa dirunut sebagai satu seri.
///
/// Maka penanda ini punya kuncinya sendiri, dibuat sekali seumur pemasangan,
/// dan tidak peduli pada pendaftaran.
class KodeNota {
  KodeNota._();

  static const _kunci = 'kode_nota_perangkat';
  static const _panjang = 4;

  /// Huruf dan angka yang tidak mudah tertukar saat dibaca manusia dari
  /// struk: tanpa 0/O, 1/I, 5/S, 8/B.
  static const _abjad = '2346789ACDEFGHJKLMNPQRTUVWXYZ';

  static const _brankas = FlutterSecureStorage();
  static String? _tersimpan;

  /// Penanda perangkat ini, dibuat saat pertama kali dibutuhkan.
  ///
  /// Kalau brankas tidak bisa dibaca — bukan hal yang mustahil di Android —
  /// penanda sementara tetap dikembalikan supaya penjualan TIDAK IKUT GAGAL.
  /// Nota tanpa penanda jauh lebih baik daripada kasir yang tidak bisa
  /// menerima uang.
  static Future<String> ambil() async {
    final adaDiMemori = _tersimpan;
    if (adaDiMemori != null) return adaDiMemori;

    try {
      final tersimpan = await _brankas.read(key: _kunci);
      if (tersimpan != null && tersimpan.isNotEmpty) {
        _tersimpan = tersimpan;
        return tersimpan;
      }
      final baru = _buat();
      await _brankas.write(key: _kunci, value: baru);
      _tersimpan = baru;
      return baru;
    } catch (_) {
      return _tersimpan ??= _buat();
    }
  }

  static String _buat() {
    final acak = Random.secure();
    return List.generate(
      _panjang,
      (_) => _abjad[acak.nextInt(_abjad.length)],
    ).join();
  }
}
