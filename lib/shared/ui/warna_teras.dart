import 'package:flutter/material.dart';

/// Palet warna UI baru, diambil apa adanya dari desain Claude Design
/// ("POS Kasir Prototype v2").
///
/// Halaman yang sudah dimigrasi WAJIB memakai warna dari sini, bukan menulis
/// `Color(0xFF...)` sendiri — supaya satu warna yang diubah di desain cukup
/// diubah di satu tempat.
abstract final class WarnaTeras {
  // Latar & permukaan
  static const latar = Color(0xFFF7F1EB);
  static const kartu = Color(0xFFFFFFFF);
  static const garis = Color(0xFFEFE8E1);
  static const latarTekan = Color(0xFFEFE6DC);

  // Oranye merek
  static const oranye = Color(0xFFF08A2C);
  static const oranyeMuda = Color(0xFFFFF1E2);
  static const oranyeLembut = Color(0xFFFDEBD8);

  // Teks
  static const teks = Color(0xFF1E1E1E);
  static const teksSedang = Color(0xFF3A3530);
  static const teksPudar = Color(0xFF8A817A);
  static const teksSamar = Color(0xFFA89E95);
  static const ikonPasif = Color(0xFF9A928B);
  static const titikPasif = Color(0xFFC4BAB1);

  // Makna
  static const merah = Color(0xFFD9483B);
  static const merahMuda = Color(0xFFFCE7E4);
  static const hijau = Color(0xFF2E8B3E);
  static const hijauMuda = Color(0xFFE6F4E8);
  static const biru = Color(0xFF3C7BD9);
}
