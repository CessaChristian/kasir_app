import 'package:flutter/material.dart';

/// Warna brand Teras Inn (orange).
const Color kSeedDineIn = Color(0xFFEE8A34);

/// Satu-satunya tempat definisi ThemeData aplikasi.
/// Semua turunan warna dihitung dari [seed] supaya ganti warna brand cukup
/// mengganti seed tanpa menyentuh halaman mana pun.
ThemeData buildAppTheme(Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    primary: seed,
    surface: Colors.white,
  );
  // Pengganti krem hardcode 0xFFF8F5F0: blend tipis seed ke off-white
  // sehingga background lembut senada brand.
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
