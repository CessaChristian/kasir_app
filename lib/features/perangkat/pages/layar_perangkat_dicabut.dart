import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../data/supabase/supabase_service.dart';

/// Ditampilkan saat pemilik mencabut perangkat ini dari halaman Perangkat.
///
/// ── KENAPA MENUTUP SELURUH LAYAR ──
///
/// Pencabutan ditolak di lapisan aturan tabel, bukan saat login. Permintaan
/// bacanya dijawab "kosong" — bukan galat — jadi tanpa layar ini aplikasinya
/// tampak baik-baik saja: menekan segarkan menghasilkan "Sudah yang terbaru",
/// dan kasir tetap melayani dengan harga yang membeku sejak dicabut.
///
/// Diam seperti itu justru yang paling berbahaya, dan berkali-kali jadi
/// sumber masalah di project ini. Maka keadaannya dinyatakan terang-terangan.
class LayarPerangkatDicabut extends StatelessWidget {
  const LayarPerangkatDicabut({super.key});

  @override
  Widget build(BuildContext context) {
    final warna = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phonelink_lock_rounded,
                    size: 40,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Perangkat Dicabut',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pemilik mencabut akses HP ini ke data toko.\n\n'
                  'Data yang sudah ada di HP ini tidak dihapus, tapi tidak '
                  'akan bertambah maupun terkirim lagi. Hubungi pemilik untuk '
                  'mendaftarkannya kembali.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      // Melepaskan identitas yang sudah tidak diakui, lalu
                      // kembali ke layar kunci — satu-satunya jalan masuk
                      // yang sah, dan tetap butuh kunci dari pemilik.
                      await SupabaseService.instance.lepaskanPerangkat();
                      PerangkatRepository.instance.dicabut.value = false;
                    },
                    icon: const Icon(Icons.key_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Daftarkan Ulang'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Butuh kunci pemasangan dari pemilik.',
                  style: TextStyle(
                    fontSize: 12,
                    color: warna.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
