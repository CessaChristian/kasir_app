import 'package:flutter/material.dart';

import 'warna_teras.dart';

/// Ikon oranye di header dengan lencana angka merah (desain): Keranjang dan
/// Open Bill. [jumlah] 0 = tanpa lencana.
class TombolBerlencana extends StatelessWidget {
  final IconData ikon;
  final String tooltip;
  final int jumlah;
  final VoidCallback onTap;

  const TombolBerlencana({
    super.key,
    required this.ikon,
    required this.tooltip,
    required this.jumlah,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(child: Icon(ikon, size: 25, color: WarnaTeras.oranye)),
              if (jumlah > 0)
                Positioned(
                  top: 2,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 19),
                    height: 19,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WarnaTeras.merah,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: WarnaTeras.latar, width: 2),
                    ),
                    child: Text(
                      '$jumlah',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
