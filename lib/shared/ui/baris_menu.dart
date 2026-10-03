import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Satu baris menu: ikon berlatar · judul + keterangan · panah.
class BarisMenu extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String? keterangan;
  final VoidCallback onTap;
  final Color warnaIkon;
  final Color latarIkon;
  final Color warnaJudul;
  final bool panah;

  const BarisMenu({
    super.key,
    required this.ikon,
    required this.judul,
    required this.onTap,
    this.keterangan,
    this.warnaIkon = WarnaTeras.oranye,
    this.latarIkon = WarnaTeras.oranyeLembut,
    this.warnaJudul = WarnaTeras.teks,
    this.panah = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: latarIkon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(ikon, size: 22, color: warnaIkon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    judul,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: warnaJudul,
                    ),
                  ),
                  if (keterangan != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      keterangan!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (panah)
              const Icon(
                Icons.chevron_right_rounded,
                color: WarnaTeras.ikonPasif,
              ),
          ],
        ),
      ),
    );
  }
}
