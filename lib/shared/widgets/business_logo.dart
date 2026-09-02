import 'package:flutter/material.dart';

/// Logo aplikasi — aset statis Teras Inn.
///
/// Dulu widget ini membaca `logo_path` dari tabel `businesses` supaya tiap
/// bisnis punya logo sendiri. Aplikasi kini difokuskan ke satu bisnis, jadi
/// logonya ikut jadi aset tetap: tidak ada lagi query DB, tidak ada file
/// yang bisa hilang, dan tidak ada lagi halaman ganti logo.
class BusinessLogo extends StatelessWidget {
  final double size;

  const BusinessLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Logo Teras Inn.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, _, _) => Icon(
        Icons.restaurant_rounded,
        size: size * 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
