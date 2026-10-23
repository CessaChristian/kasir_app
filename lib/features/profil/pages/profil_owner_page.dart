import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/baris_menu.dart';
import '../widgets/komponen_profil.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../auth/recovery/widgets/lembar_kode_recovery.dart';
import '../../owner/pages/kelola_kasir_page.dart';
import '../../perangkat/pages/daftar_perangkat_page.dart';
import '../../products/pages/kategori_page.dart';
import '../../report/pages/laporan_page.dart';
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

  /// Berapa yang perlu dicek owner (diam seminggu atau datanya bermasalah).
  int _perangkatPerluDicek = 0;

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
      final idSaya = PerangkatRepository.instance.idSaya;
      setState(() {
        _perangkatAktif = daftar.where((p) => p.aktif).length;
        _perangkatPerluDicek =
            daftar.where((p) => p.perluPerhatian(idSaya: idSaya)).length;
      });
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
        KartuAkunProfil(nama: nama, peran: 'Owner'),
        JudulBagianProfil('MENU LAINNYA'),
        KelompokMenuProfil([
          BarisMenu(
            ikon: Icons.bar_chart_rounded,
            judul: 'Laporan',
            keterangan: 'Pendapatan & produk terlaris',
            onTap: () => _buka(
              const HalamanTurunan(judul: 'Laporan', child: LaporanPage()),
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
            onTap: () => _buka(const KategoriPage()),
          ),
        ]),
        JudulBagianProfil('MANAJEMEN'),
        KelompokMenuProfil([
          BarisMenu(
            ikon: Icons.group_rounded,
            judul: 'Kelola Kasir',
            keterangan: 'Akun & akses kasir',
            warnaIkon: WarnaTeras.biru,
            latarIkon: _biru,
            onTap: () => _buka(const KelolaKasirPage()),
          ),
        ]),
        JudulBagianProfil('PERANGKAT & AKUN'),
        KelompokMenuProfil([
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
                : '$_perangkatAktif perangkat aktif'
                      '${_perangkatPerluDicek > 0 ? ' · $_perangkatPerluDicek perlu dicek' : ''}',
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
        const TombolKeluarProfil(),
      ],
    );
  }
}
