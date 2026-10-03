import 'package:flutter/material.dart';

import '../../widgets/app_toast.dart';
import '../teks_teras.dart';
import '../warna_teras.dart';
import 'lembar_periode.dart';
import 'periode.dart';

/// Kartu periode di puncak halaman: nama + tanggal, chip Reset kalau bukan
/// hari ini, dan "Ubah ▾" yang membuka [pilihPeriode].
class KartuPeriode extends StatelessWidget {
  final Periode periode;
  final ValueChanged<Periode> onBerubah;
  final DateTime? hariIni;

  const KartuPeriode({
    super.key,
    required this.periode,
    required this.onBerubah,
    this.hariIni,
  });

  @override
  Widget build(BuildContext context) {
    final h = hariIni ?? DateTime.now();
    final bukanHariIni = periode != Periode.hari(h);
    // Warna putih dan bayangan di SATU kotak. Dulu putihnya di Material dan
    // bayangannya di Container tanpa warna di atasnya — bayangan itu ikut
    // terlihat menembus kotak, kartunya jadi keabu-abuan.
    return Container(
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C230A).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final p = await pilihPeriode(context, awal: periode, hariIni: h);
            if (p != null) onBerubah(p);
          },
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranyeMuda,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 20,
                    color: WarnaTeras.oranye,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        namaPeriode(periode, h),
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                      Text(
                        labelPeriode(periode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TeksTeras.menu,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.teks,
                        ),
                      ),
                    ],
                  ),
                ),
                if (bukanHariIni) ...[
                  ChipReset(
                    onTap: () {
                      onBerubah(Periode.hari(h));
                      AppToast.info(
                        context,
                        'Filter periode direset ke hari ini',
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                ],
                const Text(
                  'Ubah',
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.oranye,
                  ),
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: WarnaTeras.oranye,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
