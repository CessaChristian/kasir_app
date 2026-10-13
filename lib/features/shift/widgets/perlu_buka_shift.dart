import 'package:flutter/material.dart';

import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../aksi_shift.dart';

/// Pengganti halaman yang butuh shift (Kasir) selama shift belum dibuka:
/// tanpa shift, kasir tidak bisa berjualan (keputusan owner 2026-10-13).
class PerluBukaShift extends StatelessWidget {
  final String keterangan;

  const PerluBukaShift({
    super.key,
    this.keterangan = 'Buka shift dulu untuk mulai berjualan.',
  });

  @override
  Widget build(BuildContext context) {
    final boleh = SessionManager.instance.hasPermission('open_close_shift');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: WarnaTeras.oranyeMuda,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                size: 32,
                color: WarnaTeras.oranye,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Shift belum dibuka',
              style: TextStyle(
                fontSize: TeksTeras.judulBagian,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              boleh
                  ? keterangan
                  : 'Akun ini tidak punya izin Buka & Tutup Shift. Minta '
                        'pemilik mengaktifkannya di Hak Akses.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: WarnaTeras.teksPudar,
              ),
            ),
            if (boleh) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 200,
                child: TombolLembar(
                  label: 'Buka Shift',
                  ikon: Icons.play_arrow_rounded,
                  latar: WarnaTeras.oranye,
                  warna: Colors.white,
                  tinggi: 46,
                  sudut: 12,
                  onPressed: () => bukaShiftLewatDialog(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
