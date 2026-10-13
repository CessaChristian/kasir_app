import 'package:flutter/material.dart';

import '../../utils/sapaan.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// Baris pembuka kartu dashboard (desain): ikon · "Selamat siang," + nama ·
/// [lencana] di kanan.
class KepalaSapaan extends StatelessWidget {
  final String nama;
  final IconData ikon;
  final Color latarIkon;
  final Color warnaIkon;
  final Widget lencana;

  const KepalaSapaan({
    super.key,
    required this.nama,
    required this.ikon,
    required this.lencana,
    this.latarIkon = WarnaTeras.oranyeLembut,
    this.warnaIkon = WarnaTeras.oranye,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: latarIkon,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(ikon, size: 22, color: warnaIkon),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selamat ${sapaanWaktu(DateTime.now()).toLowerCase()},',
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  color: WarnaTeras.teksSedang,
                ),
              ),
              Text(
                nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.teks,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        lencana,
      ],
    );
  }
}

/// Lencana bulat kecil berikon di kanan [KepalaSapaan].
class LencanaSapaan extends StatelessWidget {
  final String teks;
  final IconData? ikon;
  final Color latar;
  final Color warna;

  const LencanaSapaan(
    this.teks, {
    super.key,
    this.ikon,
    this.latar = WarnaTeras.oranyeLembut,
    this.warna = WarnaTeras.oranye,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 14, color: warna),
            const SizedBox(width: 4),
          ],
          Text(
            teks,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w600,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}
