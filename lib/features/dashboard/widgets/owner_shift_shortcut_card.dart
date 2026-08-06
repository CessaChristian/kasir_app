import 'package:flutter/material.dart';

import '../../shift/pages/shift_monitor_page.dart';

/// Kartu pintasan di dashboard OWNER menuju Halaman Pantau Shift.
///
/// Menggantikan kartu "Shift Aktif" (yang untuk cashier menampilkan shift
/// dirinya). Owner tidak menjalankan shift, jadi kartu ini statis — hanya
/// pintu masuk ke [ShiftMonitorPage].
///
/// TODO (Phase 2 / sync): setelah sinkronisasi database aktif, kartu ini bisa
/// diperkaya menampilkan ringkasan LIVE shift kasir yang sedang berjalan
/// (siapa buka shift + jumlah transaksi berjalan). Sebelum sync, device owner
/// belum punya data shift kasir secara live.
class OwnerShiftShortcutCard extends StatelessWidget {
  const OwnerShiftShortcutCard({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShiftMonitorPage()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.monitor_heart_outlined,
                      color: primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pantau Shift Kasir ',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lihat riwayat & rincian shift kasir',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
