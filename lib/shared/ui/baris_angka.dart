import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Satu kolom di [BarisAngka].
class Angka {
  final String label;
  final String nilai;
  final Color warna;

  const Angka(this.label, this.nilai, {this.warna = WarnaTeras.teks});
}

/// Beberapa angka sejajar dengan garis pemisah, mis. Transaksi · Pengeluaran
/// · Laba kotor.
class BarisAngka extends StatelessWidget {
  final List<Angka> isi;

  const BarisAngka({super.key, required this.isi});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < isi.length; i++)
          Expanded(
            child: Container(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
              decoration: i == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(left: BorderSide(color: WarnaTeras.garis)),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isi[i].label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isi[i].nilai,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isi[i].warna,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
