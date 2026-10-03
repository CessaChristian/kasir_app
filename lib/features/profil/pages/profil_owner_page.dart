import 'package:flutter/material.dart';

import '../../../app/keluar_akun.dart';
import '../../../shared/ui/baris_menu.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../owner/pages/manage_cashiers_page.dart';
import '../../perangkat/pages/daftar_perangkat_page.dart';
import '../../products/category_manager.dart';
import '../../report/report_page.dart';
import '../../shift/pages/shift_monitor_page.dart';

/// Tab Profil owner — VERSI SEMENTARA: daftar polos menuju halaman yang
/// dulu ada di drawer. Tampilan sesuai desain (kartu akun + kelompok menu)
/// menyusul saat halaman Profil dimigrasi.
///
/// Seluruh halaman ini hanya terjangkau owner (lewat `KerangkaOwner`), jadi
/// Kelola Kasir dan Perangkat di sini tetap hak paten owner.
class ProfilOwnerPage extends StatelessWidget {
  const ProfilOwnerPage({super.key});

  void _buka(BuildContext context, Widget halaman) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => halaman));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        KartuTeras(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              BarisMenu(
                ikon: Icons.bar_chart_rounded,
                judul: 'Laporan',
                onTap: () => _buka(
                  context,
                  const HalamanTurunan(judul: 'Laporan', child: ReportPage()),
                ),
              ),
              BarisMenu(
                ikon: Icons.history_rounded,
                judul: 'Riwayat Shift',
                onTap: () => _buka(context, const ShiftMonitorPage()),
              ),
              BarisMenu(
                ikon: Icons.category_rounded,
                judul: 'Kategori',
                onTap: () => CategoryManager.show(context),
              ),
              BarisMenu(
                ikon: Icons.group_rounded,
                judul: 'Kelola Kasir',
                onTap: () => _buka(context, const ManageCashiersPage()),
              ),
              BarisMenu(
                ikon: Icons.devices_rounded,
                judul: 'Perangkat Terdaftar',
                onTap: () => _buka(context, const DaftarPerangkatPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KartuTeras(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: BarisMenu(
            ikon: Icons.logout_rounded,
            judul: 'Keluar',
            warnaIkon: WarnaTeras.merah,
            latarIkon: WarnaTeras.merahMuda,
            warnaJudul: WarnaTeras.merah,
            panah: false,
            onTap: () => keluarDariAkun(context),
          ),
        ),
      ],
    );
  }
}
