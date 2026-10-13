import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'tombol_lembar.dart';
import 'warna_teras.dart';

/// Layar "Tidak ada koneksi internet" (desain Daftar Perangkat) untuk
/// halaman yang wajib online: ikon, [keterangan], dua saran, dan tombol
/// Coba lagi. [memeriksa] = sedang mencoba menghubungi server.
class LayarButuhInternet extends StatelessWidget {
  final String keterangan;
  final bool memeriksa;
  final VoidCallback onCobaLagi;

  const LayarButuhInternet({
    super.key,
    required this.keterangan,
    required this.memeriksa,
    required this.onCobaLagi,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: WarnaTeras.latarAbu,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: WarnaTeras.teksPudar,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tidak ada koneksi internet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              keterangan,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TeksTeras.biasa,
                height: 1.5,
                color: Color(0xFF6B6058),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: WarnaTeras.kartu,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  _Saran(
                    Icons.wifi_rounded,
                    'Nyalakan Wi-Fi atau data seluler',
                  ),
                  SizedBox(height: 10),
                  _Saran(
                    Icons.airplanemode_inactive_rounded,
                    'Pastikan mode pesawat mati',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: TombolLembar(
              label: memeriksa ? 'Menghubungkan…' : 'Coba lagi',
              ikon: Icons.refresh_rounded,
              latar: WarnaTeras.oranye,
              warna: Colors.white,
              tinggi: 46,
              sudut: 10,
              ukuranTeks: 15,
              onPressed: memeriksa ? null : onCobaLagi,
            ),
          ),
        ),
      ],
    );
  }
}

class _Saran extends StatelessWidget {
  final IconData ikon;
  final String teks;

  const _Saran(this.ikon, this.teks);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(ikon, size: 20, color: WarnaTeras.oranye),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            teks,
            style: const TextStyle(fontSize: 13, color: WarnaTeras.teksSedang),
          ),
        ),
      ],
    );
  }
}
