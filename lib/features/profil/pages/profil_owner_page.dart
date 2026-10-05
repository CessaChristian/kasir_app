import 'package:flutter/material.dart';

import '../../../app/keluar_akun.dart';
import '../../../data/perangkat/perangkat_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/ui/baris_menu.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../auth/recovery/widgets/lembar_kode_recovery.dart';
import '../../owner/pages/manage_cashiers_page.dart';
import '../../perangkat/pages/daftar_perangkat_page.dart';
import '../../products/category_manager.dart';
import '../../report/report_page.dart';
import '../../shift/pages/riwayat_shift_page.dart';

/// Profil owner (desain): kartu akun · MENU LAINNYA · MANAJEMEN ·
/// PERANGKAT & AKUN · Keluar · versi.
///
/// Seluruh halaman ini hanya terjangkau owner (lewat `KerangkaOwner`), jadi
/// Kelola Kasir dan Perangkat di sini tetap hak paten owner. Menu yang belum
/// dimigrasi membuka halaman lamanya dulu.
class ProfilOwnerPage extends StatefulWidget {
  const ProfilOwnerPage({super.key});

  @override
  State<ProfilOwnerPage> createState() => _ProfilOwnerPageState();
}

class _ProfilOwnerPageState extends State<ProfilOwnerPage> {
  /// "N perangkat aktif" — null selama memuat atau kalau server tak
  /// terjangkau (offline).
  int? _perangkatAktif;

  static const _biru = Color(0xFFE8F0FB);

  @override
  void initState() {
    super.initState();
    _muatPerangkat();
  }

  Future<void> _muatPerangkat() async {
    try {
      final daftar = await PerangkatRepository.instance.semua();
      if (!mounted || daftar.isEmpty) return;
      setState(() => _perangkatAktif = daftar.where((p) => p.aktif).length);
    } catch (_) {
      // Offline: keterangan umum tetap tampil.
    }
  }

  void _buka(Widget halaman) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => halaman),
      );

  @override
  Widget build(BuildContext context) {
    final nama = SessionManager.instance.currentSession?.username ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _kartuAkun(nama),
        _judulBagian('MENU LAINNYA'),
        _kelompok([
          BarisMenu(
            ikon: Icons.bar_chart_rounded,
            judul: 'Laporan',
            keterangan: 'Pendapatan & produk terlaris',
            onTap: () => _buka(
              const HalamanTurunan(judul: 'Laporan', child: ReportPage()),
            ),
          ),
          BarisMenu(
            ikon: Icons.history_rounded,
            judul: 'Riwayat Shift',
            keterangan: 'Semua shift kasir',
            onTap: () => _buka(const RiwayatShiftPage()),
          ),
          BarisMenu(
            ikon: Icons.category_rounded,
            judul: 'Kategori',
            keterangan: 'Atur kategori & tampilan di Kasir',
            onTap: () => CategoryManager.show(context),
          ),
        ]),
        _judulBagian('MANAJEMEN'),
        _kelompok([
          BarisMenu(
            ikon: Icons.group_rounded,
            judul: 'Kelola Kasir',
            keterangan: 'Akun & akses kasir',
            warnaIkon: WarnaTeras.biru,
            latarIkon: _biru,
            onTap: () => _buka(const ManageCashiersPage()),
          ),
        ]),
        _judulBagian('PERANGKAT & AKUN'),
        _kelompok([
          BarisMenu(
            ikon: Icons.print_rounded,
            judul: 'Printer Struk',
            keterangan: 'Printer Bluetooth',
            warnaIkon: WarnaTeras.hijau,
            latarIkon: WarnaTeras.hijauMuda,
            // Fitur printer belum dibuat. Menu tetap tampil sesuai desain,
            // tapi belum melakukan apa-apa — tanpa pesan (keputusan owner
            // 2026-10-04).
            onTap: () {},
          ),
          BarisMenu(
            ikon: Icons.devices_rounded,
            judul: 'Perangkat Terdaftar',
            keterangan: _perangkatAktif == null
                ? 'HP yang terhubung ke toko'
                : '$_perangkatAktif perangkat aktif',
            warnaIkon: WarnaTeras.biru,
            latarIkon: _biru,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DaftarPerangkatPage()),
              );
              // Owner bisa mencabut/melupakan HP di sana.
              _muatPerangkat();
            },
          ),
          BarisMenu(
            ikon: Icons.key_rounded,
            judul: 'Kode Recovery',
            keterangan: 'Buat kode untuk reset PIN Owner',
            latarIkon: WarnaTeras.oranyeMuda,
            onTap: () => perbaruiKodeRecovery(context),
          ),
        ]),
        const SizedBox(height: 22),
        Material(
          color: WarnaTeras.kartu,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => keluarDariAkun(context),
            child: const SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 21, color: WarnaTeras.merah),
                  SizedBox(width: 8),
                  Text(
                    'Keluar',
                    style: TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.merah,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${AppConstants.storeName} POS · v${AppConstants.versiAplikasi}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.kecil,
            color: WarnaTeras.teksSamar,
          ),
        ),
      ],
    );
  }

  Widget _kartuAkun(String nama) {
    return KartuTeras(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WarnaTeras.oranyeLembut,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              nama.isEmpty ? '?' : nama.characters.first.toUpperCase(),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  style: const TextStyle(
                    fontSize: TeksTeras.judulBagian,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranyeLembut,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 14,
                        color: WarnaTeras.oranye,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Owner',
                        style: TextStyle(
                          fontSize: TeksTeras.kecil,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _judulBagian(String teks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        teks,
        style: const TextStyle(
          fontSize: TeksTeras.kecil,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: WarnaTeras.teksSamar,
        ),
      ),
    );
  }

  Widget _kelompok(List<Widget> isi) {
    return KartuTeras(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: isi),
    );
  }
}
