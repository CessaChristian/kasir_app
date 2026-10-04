import 'package:flutter/material.dart';

import '../../../data/sync/kemajuan_sync.dart';
import '../../../data/sync/sync_service.dart';
import '../warna_teras.dart';
import 'pengendali_segarkan.dart';
import '../teks_teras.dart';

/// Pita di bawah header yang turun saat refresh: ikon · judul · keterangan,
/// dan bilah kemajuan tipis.
class PitaSinkron extends StatelessWidget {
  final PengendaliSegarkan pengendali;

  const PitaSinkron({super.key, required this.pengendali});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pengendali,
      builder: (context, _) => AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: pengendali.pitaTerlihat
            ? ValueListenableBuilder<KemajuanSync?>(
                valueListenable: SyncService.instance.kemajuan,
                builder: (context, kemajuan, _) => _isi(kemajuan),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  Widget _isi(KemajuanSync? kemajuan) {
    final keadaan = pengendali.keadaan;
    final teks = teksPita(keadaan, pengendali.hasil, kemajuan);
    final rasio = switch (keadaan) {
      KeadaanSegarkan.berjalan => kemajuan?.rasio ?? 0.0,
      _ => 1.0,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        border: Border.all(color: WarnaTeras.garisOranye),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranyeMuda,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(teks.ikon, size: 18, color: WarnaTeras.oranye),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teks.judul,
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        teks.keterangan,
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 3,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: rasio),
              duration: const Duration(milliseconds: 500),
              builder: (context, nilai, _) => LinearProgressIndicator(
                value: nilai,
                minHeight: 3,
                color: WarnaTeras.oranye,
                backgroundColor: WarnaTeras.latarBilah,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
