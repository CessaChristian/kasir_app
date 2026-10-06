import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'tombol_lembar.dart';
import 'warna_teras.dart';

/// Lembar konfirmasi dari bawah (desain): ikon · judul · catatan ·
/// [Batal] [aksi]. Mengembalikan true kalau aksi ditekan.
///
/// Dipakai "Hapus produk?"; nanti juga "Keluar dari akun?", "Reset PIN",
/// dan konfirmasi serupa.
Future<bool> tampilkanLembarKonfirmasi(
  BuildContext context, {
  required IconData ikon,
  required String judul,
  required String catatan,
  required String labelAksi,
  Color warnaAksi = WarnaTeras.merah,
  Color latarIkon = WarnaTeras.merahMuda,
}) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
            child: Icon(ikon, size: 28, color: warnaAksi),
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
              fontSize: TeksTeras.biasa,
              height: 1.45,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TombolLembar(
                  label: 'Batal',
                  latar: WarnaTeras.latarAbu,
                  warna: WarnaTeras.teks,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 10),
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
  );
  return hasil == true;
}
