import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/sync/kemajuan_sync.dart';
import '../../data/sync/sync_service.dart';

/// Popup yang menampilkan jalannya sinkronisasi: sedang menarik tabel apa,
/// sudah berapa baris dari berapa.
///
/// Menarik seribu baris lewat jaringan ponsel bisa lebih dari semenit. Tanpa
/// tampilan ini layar diam total — pengguna menyimpulkan aplikasinya
/// menggantung lalu menekan tombol berulang kali. Ini juga yang membuat
/// pengembang sulit tahu sinkron macet di titik mana.
///
/// SENGAJA tidak bisa ditutup dengan menekan di luar atau tombol back:
/// menutupnya tidak menghentikan sinkron, jadi menutupnya hanya membuat
/// pengguna mengira prosesnya batal.
class DialogSync extends StatelessWidget {
  const DialogSync({super.key});

  /// Tampilkan popup, jalankan [proses], lalu tutup popupnya.
  ///
  /// Popup ditutup lewat Navigator milik dialog itu sendiri supaya tidak
  /// ikut menutup halaman di bawahnya kalau pemanggilnya sudah berpindah.
  static Future<T> tampilkanSelama<T>(
    BuildContext context,
    Future<T> Function() proses,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);

    // Sengaja TIDAK ditunggu: showDialog baru selesai saat dialognya ditutup,
    // dan yang menutupnya justru blok `finally` di bawah.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: DialogSync(),
      ),
    ));

    try {
      return await proses();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final warna = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: ValueListenableBuilder<KemajuanSync?>(
          valueListenable: SyncService.instance.kemajuan,
          builder: (context, k, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    // Selagi belum ada laporan pertama, putaran tanpa nilai
                    // lebih jujur daripada bilah 0% yang terlihat macet.
                    value: k?.rasio,
                    strokeWidth: 4,
                    color: warna,
                    backgroundColor: warna.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  k == null ? 'Menyambung…' : 'Menyinkronkan Data',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  k == null
                      ? 'Menghubungi server'
                      : '${k.tahap == 'menarik' ? 'Mengambil' : 'Mengirim'} '
                          '${k.namaRamah}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (k != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: k.rasio,
                      minHeight: 6,
                      color: warna,
                      backgroundColor: warna.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${k.baris} dari ${k.totalBaris} data',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Tahap ${k.entitasKe}/${k.totalEntitas}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
