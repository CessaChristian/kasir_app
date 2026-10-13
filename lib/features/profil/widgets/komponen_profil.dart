import 'package:flutter/material.dart';

import '../../../app/keluar_akun.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';

/// Kartu akun di puncak Profil (desain): inisial · nama · lencana peran.
class KartuAkunProfil extends StatelessWidget {
  final String nama;

  /// "Owner" atau "Kasir".
  final String peran;

  const KartuAkunProfil({super.key, required this.nama, required this.peran});

  @override
  Widget build(BuildContext context) {
    return KartuTeras(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WarnaTeras.oranyeLembut,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              nama.isEmpty ? '?' : nama.characters.first.toUpperCase(),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  style: const TextStyle(
                    fontSize: TeksTeras.judulBagian,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranyeLembut,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        size: 14,
                        color: WarnaTeras.oranye,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        peran,
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Judul kelompok menu Profil, mis. "MENU LAINNYA".
class JudulBagianProfil extends StatelessWidget {
  final String teks;

  const JudulBagianProfil(this.teks, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        teks,
        style: const TextStyle(
          fontSize: TeksTeras.kecil,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: WarnaTeras.teksSamar,
        ),
      ),
    );
  }
}

/// Satu kartu berisi beberapa baris menu.
class KelompokMenuProfil extends StatelessWidget {
  final List<Widget> isi;

  const KelompokMenuProfil(this.isi, {super.key});

  @override
  Widget build(BuildContext context) {
    return KartuTeras(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: isi),
    );
  }
}

/// Tombol Keluar merah + versi aplikasi di dasar Profil.
class TombolKeluarProfil extends StatelessWidget {
  const TombolKeluarProfil({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        Material(
          color: WarnaTeras.kartu,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => keluarDariAkun(context),
            child: const SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 21, color: WarnaTeras.merah),
                  SizedBox(width: 8),
                  Text(
                    'Keluar',
                    style: TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.merah,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${AppConstants.storeName} POS · v${AppConstants.versiAplikasi}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.kecil,
            color: WarnaTeras.teksSamar,
          ),
        ),
      ],
    );
  }
}
