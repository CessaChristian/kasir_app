import 'package:flutter/material.dart';

import '../../widgets/app_toast.dart';
import '../teks_teras.dart';
import '../warna_teras.dart';
import 'lembar_periode.dart';
import 'metode_filter.dart';
import 'periode.dart';

/// Kartu periode di puncak halaman: nama + tanggal, chip Reset kalau bukan
/// hari ini, dan "Ubah ▾" yang membuka [pilihPeriode].
class KartuPeriode extends StatelessWidget {
  final Periode periode;
  final ValueChanged<Periode> onBerubah;
  final DateTime? hariIni;

  /// Diisi = mode filter Riwayat (ikon ⚙, metode bayar ikut disaring).
  final MetodeFilter? metode;
  final ValueChanged<MetodeFilter>? onBerubahMetode;

  const KartuPeriode({
    super.key,
    required this.periode,
    required this.onBerubah,
    this.hariIni,
    this.metode,
    this.onBerubahMetode,
  });

  @override
  Widget build(BuildContext context) {
    final h = hariIni ?? DateTime.now();
    final m = metode;
    final bukanBawaan =
        periode != Periode.hari(h) || (m != null && m != MetodeFilter.semua);
    final nama = m == null || m == MetodeFilter.semua
        ? namaPeriode(periode, h)
        : '${namaPeriode(periode, h)} · ${m.label}';
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
            if (m == null) {
              final p = await pilihPeriode(context, awal: periode, hariIni: h);
              if (p != null) onBerubah(p);
              return;
            }
            final f = await pilihFilterRiwayat(
              context,
              awal: periode,
              metode: m,
              hariIni: h,
            );
            if (f == null) return;
            onBerubah(f.periode);
            onBerubahMetode?.call(f.metode);
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
                  child: Icon(
                    m == null
                        ? Icons.calendar_month_rounded
                        : Icons.tune_rounded,
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
                        nama,
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
                if (bukanBawaan) ...[
                  ChipReset(
                    onTap: () {
                      onBerubah(Periode.hari(h));
                      if (m != null) onBerubahMetode?.call(MetodeFilter.semua);
                      AppToast.info(
                        context,
                        m == null
                            ? 'Filter periode direset ke hari ini'
                            : 'Filter direset',
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
