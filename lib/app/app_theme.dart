import 'package:flutter/material.dart';

/// Warna brand per tipe business — HARDCODE sesuai keputusan client
/// (spec 2026-07-18 REVISI 2, D4). Teras Inn (dine-in) = orange existing;
/// Thai Tea (grab-and-go) = monokrom hitam-putih sementara sampai client
/// menentukan warna brand-nya.
const Color kSeedDineIn = Color(0xFFEE8A34);
const Color kSeedGrabGo = Color(0xFF212121);

Color seedForBusinessType(String? type) =>
    type == 'beverage_grabgo' ? kSeedGrabGo : kSeedDineIn;

/// Satu-satunya tempat definisi ThemeData aplikasi.
/// Semua turunan warna dihitung dari [seed] supaya ganti business cukup
/// mengganti seed tanpa menyentuh halaman mana pun.
ThemeData buildAppTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    primary: seed,
    surface: Colors.white,
  );
  // Pengganti krem hardcode 0xFFF8F5F0: blend tipis seed ke off-white
  // sehingga tiap business dapat background lembut senada brand-nya.
  final softBackground = Color.alphaBlend(
    seed.withValues(alpha: 0.05),
    const Color(0xFFFAF9F7),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: softBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
  );
}
