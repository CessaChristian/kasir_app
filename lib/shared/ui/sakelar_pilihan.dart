import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Kartu sakelar (desain form produk): ikon berwarna · judul + keterangan ·
/// sakelar. Seluruh kartu bisa diketuk.
class SakelarPilihan extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String keterangan;
  final bool nilai;
  final Color warna;

  /// Latar jalur sakelar saat menyala.
  final Color jalur;
  final ValueChanged<bool> onUbah;

  const SakelarPilihan({
    super.key,
    required this.ikon,
    required this.judul,
    required this.keterangan,
    required this.nilai,
    required this.warna,
    required this.jalur,
    required this.onUbah,
  });

  @override
  Widget build(BuildContext context) {
    const abu = Color(0xFFECEAE8);
    return Semantics(
      toggled: nilai,
      label: judul,
      child: GestureDetector(
        onTap: () => onUbah(!nilai),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: nilai ? const Color(0xFFFAF3EC) : abu,
            border: Border.all(color: nilai ? warna : abu),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: nilai ? warna : const Color(0xFFA3A3A3),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(ikon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      judul,
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        color: nilai ? warna : WarnaTeras.teks,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      keterangan,
                      style: const TextStyle(
                        fontSize: TeksTeras.keterangan,
                        color: WarnaTeras.teksSamar,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _sakelar(),
            ],
          ),
        ),
      ),
    );
  }

  /// Sakelar 48×26 bertepi, kenop bergeser (desain).
  Widget _sakelar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48,
      height: 26,
      decoration: BoxDecoration(
        color: nilai ? jalur : Colors.white,
        border: Border.all(
          color: nilai ? warna : const Color(0xFF6B6058),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: nilai ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 19,
          height: 19,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: nilai ? warna : WarnaTeras.teks,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
