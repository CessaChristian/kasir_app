import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/business_logo.dart';
import 'warna_teras.dart';

/// Header halaman di UI baru: logo (atau tombol kembali) · judul · tanggal.
///
/// Halaman utama (tab di nav bawah) memakai logo. Halaman turunan memberi
/// [onKembali], dan logonya diganti panah kembali.
class HeaderTeras extends StatelessWidget {
  final String judul;
  final VoidCallback? onKembali;

  const HeaderTeras({super.key, required this.judul, this.onKembali});

  @override
  Widget build(BuildContext context) {
    final sekarang = DateTime.now();
    return Container(
      height: 52,
      color: WarnaTeras.latar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (onKembali != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: onKembali,
                icon: const Icon(Icons.arrow_back_rounded),
                color: WarnaTeras.teks,
                tooltip: 'Kembali',
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: BusinessLogo(size: 34),
            ),
          Expanded(
            child: Text(
              judul,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('EEEE', 'id_ID').format(sekarang),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.teks,
                ),
              ),
              Text(
                DateFormat('d MMM yyyy', 'id_ID').format(sekarang),
                style: const TextStyle(
                  fontSize: 11,
                  color: WarnaTeras.teksSedang,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
