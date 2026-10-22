import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'tombol_lembar.dart';
import 'warna_teras.dart';

/// Dialog konfirmasi di tengah layar (desain "Tutup shift sekarang?"):
/// ikon · judul · catatan · [Batal] [aksi]. True kalau aksi ditekan.
/// [labelBatal] null = hanya tombol aksi (pemberitahuan, bukan pertanyaan).
Future<bool> tampilkanDialogTengah(
  BuildContext context, {
  required IconData ikon,
  required String judul,
  required String catatan,
  required String labelAksi,
  Color warnaAksi = WarnaTeras.merah,
  Color latarIkon = WarnaTeras.merahMuda,
  Color? warnaIkon,
  String? labelBatal = 'Batal',
}) async {
  final hasil = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: WarnaTeras.kartu,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: latarIkon,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(ikon, size: 28, color: warnaIkon ?? warnaAksi),
            ),
            const SizedBox(height: 12),
            Text(
              judul,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TeksTeras.judulBagian,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              catatan,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (labelBatal != null) ...[
                  Expanded(
                    child: TombolLembar(
                      label: labelBatal,
                      latar: WarnaTeras.latarAbu,
                      warna: WarnaTeras.teks,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TombolLembar(
                    label: labelAksi,
                    latar: warnaAksi,
                    warna: Colors.white,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return hasil == true;
}
