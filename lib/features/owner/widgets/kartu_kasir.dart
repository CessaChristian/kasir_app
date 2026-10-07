import 'package:flutter/material.dart';

import '../../../shared/ui/sakelar.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/ui/inisial_akun.dart';
import '../models/ringkasan_kasir.dart';

/// Kartu satu kasir di Kelola Kasir (desain): inisial · nama · status shift
/// · sakelar aktif · ⋮, ringkasan hak akses, lalu Hak Akses dan Reset PIN.
/// Akun nonaktif tampil pudar.
class KartuKasir extends StatelessWidget {
  final RingkasanKasir ringkasan;
  final DateTime sekarang;
  final ValueChanged<bool> onUbahAktif;
  final VoidCallback onMenu;
  final VoidCallback onHakAkses;
  final VoidCallback onResetPin;

  const KartuKasir({
    super.key,
    required this.ringkasan,
    required this.sekarang,
    required this.onUbahAktif,
    required this.onMenu,
    required this.onHakAkses,
    required this.onResetPin,
  });

  @override
  Widget build(BuildContext context) {
    final r = ringkasan;
    final aktif = r.akun.isActive;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: aktif ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WarnaTeras.kartu,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InisialKasir(nama: r.akun.username, ukuran: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.akun.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TeksTeras.menu,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        labelStatusShift(
                          mulaiBerjalan: r.mulaiShiftBerjalan,
                          selesaiTerakhir: r.selesaiShiftTerakhir,
                          sekarang: sekarang,
                        ),
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Sakelar(
                  nilai: aktif,
                  onUbah: onUbahAktif,
                  label: 'Akun ${r.akun.username} aktif',
                ),
                IconButton(
                  onPressed: onMenu,
                  tooltip: 'Menu akun',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: WarnaTeras.oranye,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${r.izinAktif} dari ${r.izinTotal} hak akses aktif',
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: WarnaTeras.garis)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _tombol(
                      ikon: Icons.admin_panel_settings_rounded,
                      label: 'Hak Akses',
                      onTap: onHakAkses,
                      latar: WarnaTeras.oranyeMuda,
                      warna: WarnaTeras.oranye,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _tombol(
                      ikon: Icons.lock_reset_rounded,
                      label: 'Reset PIN',
                      onTap: onResetPin,
                      latar: WarnaTeras.kartu,
                      warna: const Color(0xFF5A5048),
                      tepi: const Color(0xFFE6DED6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tombol({
    required IconData ikon,
    required String label,
    required VoidCallback onTap,
    required Color latar,
    required Color warna,
    Color? tepi,
  }) {
    final bentuk = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: tepi == null ? BorderSide.none : BorderSide(color: tepi),
    );
    return Material(
      color: latar,
      shape: bentuk,
      child: InkWell(
        onTap: onTap,
        customBorder: bentuk,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ikon, size: 19, color: warna),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: warna,
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
