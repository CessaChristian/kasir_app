import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// "Masuk setelah shift ditutup" di bawah transaksi/pengeluaran yang dicatat
/// SESUDAH shift-nya ditutup — biasanya dari HP yang sedang offline saat HP
/// lain menutup shift. Owner jadi tahu kenapa kas akhir shift berubah
/// setelah diserahkan.
class KeteranganSetelahTutup extends StatelessWidget {
  final double ukuran;

  const KeteranganSetelahTutup({super.key, this.ukuran = 13});

  static const teks = 'Masuk setelah shift ditutup';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: ukuran + 2,
            color: WarnaTeras.oranye,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              teks,
              style: TextStyle(
                fontSize: ukuran,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
