import 'package:flutter/material.dart';

import '../../shared/services/catatan_error.dart';
import '../../utils/pesan_galat.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// Pengganti lingkaran muat saat datanya GAGAL dimuat — dulu Laporan dan
/// Dashboard owner berputar selamanya tanpa pesan (review D1/D2).
class GalatMuat extends StatelessWidget {
  final Object galat;

  /// Kalimat untuk galat yang tidak dikenali, mis. "Laporan gagal dimuat".
  final String awalan;
  final VoidCallback onCobaLagi;

  const GalatMuat({
    super.key,
    required this.galat,
    required this.awalan,
    required this.onCobaLagi,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: WarnaTeras.teksSamar,
          ),
          const SizedBox(height: 10),
          Text(
            pesanGalat(galat, awalan: awalan),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TeksTeras.biasa,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onCobaLagi,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba lagi'),
            style: TextButton.styleFrom(foregroundColor: WarnaTeras.oranye),
          ),
        ],
      ),
    );
  }
}

/// Untuk bagian PELENGKAP layar (produk laris, kartu info shift) yang
/// sengaja tidak menampilkan kotak galat: kalau alirannya gagal, bagiannya
/// tetap disembunyikan seperti biasa tetapi galatnya DICATAT supaya sampai
/// ke server. Dulu galat seperti ini ditelan diam-diam.
///
/// Aman dipanggil di setiap build: galat yang sama hanya dicatat sekali.
void catatGalatAliran(AsyncSnapshot<Object?> snap, String sumber) {
  if (!snap.hasError) return;
  CatatanError.instance.catat(snap.error!, snap.stackTrace, sumber: sumber);
}
