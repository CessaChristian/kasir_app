import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/baris_menu.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../products/pages/kategori_page.dart';
import '../../products/pages/products_page.dart';
import '../../report/pages/laporan_page.dart';
import '../../shift/aksi_shift.dart';
import '../../shift/models/ringkasan_shift.dart';
import '../../shift/pages/riwayat_shift_page.dart';
import '../../shift/repositories/shift_repository.dart';
import '../widgets/komponen_profil.dart';

/// Profil kasir (desain): kartu akun · kartu shift (Buka/Tutup shift) ·
/// MENU LAINNYA · PERANGKAT & AKUN · Keluar.
///
/// Menu yang butuh izin (Produk, Kategori, Laporan) hanya muncul kalau
/// izinnya diberikan owner — dulu tempatnya di menu samping (keputusan owner
/// 2026-10-13).
class ProfilKasirPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final ShiftRepository? repo;

  const ProfilKasirPage({super.key, this.repo});

  @override
  State<ProfilKasirPage> createState() => _ProfilKasirPageState();
}

class _ProfilKasirPageState extends State<ProfilKasirPage> {
  late final _repo = widget.repo ?? ShiftRepository(db);
  String? _kunci;
  Stream<RingkasanShift?>? _aliran;

  @override
  void initState() {
    super.initState();
    SessionManager.instance.sesiBerubah.addListener(_segarkan);
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_segarkan);
    super.dispose();
  }

  void _segarkan() {
    if (mounted) setState(() {});
  }

  Stream<RingkasanShift?>? _shift(String? shiftId) {
    if (shiftId != _kunci) {
      _kunci = shiftId;
      _aliran = shiftId == null ? null : _repo.watchShift(shiftId);
    }
    return _aliran;
  }

  void _buka(Widget halaman) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => halaman));

  @override
  Widget build(BuildContext context) {
    final sm = SessionManager.instance;
    final sesi = sm.currentSession;
    final semuaShift = sm.hasPermission('view_all_shifts');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        KartuAkunProfil(nama: sesi?.username ?? '', peran: 'Kasir'),
        const SizedBox(height: 10),
        StreamBuilder<RingkasanShift?>(
          stream: _shift(sesi?.shiftId),
          builder: (context, snap) =>
              _kartuShift(sesi?.shiftId != null, snap.data),
        ),
        const JudulBagianProfil('MENU LAINNYA'),
        KelompokMenuProfil([
          BarisMenu(
            ikon: Icons.history_rounded,
            judul: 'Riwayat Shift',
            keterangan: semuaShift ? 'Semua shift kasir' : 'Shift saya',
            onTap: () => _buka(const RiwayatShiftPage()),
          ),
          if (sm.hasPermission('manage_products'))
            BarisMenu(
              ikon: Icons.shopping_basket_rounded,
              judul: 'Produk',
              keterangan: 'Kelola produk',
              onTap: () => _buka(
                const HalamanTurunan(judul: 'Produk', child: ProductsPage()),
              ),
            ),
          if (sm.hasPermission('manage_categories'))
            BarisMenu(
              ikon: Icons.category_rounded,
              judul: 'Kategori',
              keterangan: 'Atur kategori & tampilan di Kasir',
              onTap: () => _buka(const KategoriPage()),
            ),
          if (sm.hasPermission('view_report'))
            BarisMenu(
              ikon: Icons.bar_chart_rounded,
              judul: 'Laporan',
              keterangan: 'Pendapatan & produk terlaris',
              onTap: () => _buka(
                const HalamanTurunan(judul: 'Laporan', child: LaporanPage()),
              ),
            ),
        ]),
        const JudulBagianProfil('PERANGKAT & AKUN'),
        KelompokMenuProfil([
          BarisMenu(
            ikon: Icons.print_rounded,
            judul: 'Printer Struk',
            keterangan: 'Printer Bluetooth',
            warnaIkon: WarnaTeras.hijau,
            latarIkon: WarnaTeras.hijauMuda,
            // Fitur printer belum dibuat — sama dengan Profil owner.
            onTap: () {},
          ),
        ]),
        const TombolKeluarProfil(),
      ],
    );
  }

  Widget _kartuShift(bool berjalan, RingkasanShift? r) {
    final boleh = SessionManager.instance.hasPermission('open_close_shift');
    final keterangan = !berjalan
        ? 'Buka shift untuk mulai berjualan'
        : r == null
        ? 'Memuat…'
        : 'Mulai ${DateFormat('HH:mm').format(r.shift.startAt)} · '
              '${r.jumlahTransaksi} transaksi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WarnaTeras.garisOranye),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: berjalan ? WarnaTeras.hijau : WarnaTeras.titikPasif,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  berjalan ? 'Shift aktif' : 'Shift belum dibuka',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  keterangan,
                  style: const TextStyle(
                    fontSize: TeksTeras.keterangan,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ],
            ),
          ),
          if (boleh)
            OutlinedButton(
              onPressed: () => berjalan
                  ? tutupShiftLewatDialog(context, repo: _repo)
                  : bukaShiftLewatDialog(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: WarnaTeras.oranye,
                backgroundColor: WarnaTeras.kartu,
                side: const BorderSide(color: WarnaTeras.oranye),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                berjalan ? 'Tutup shift' : 'Buka shift',
                style: const TextStyle(
                  fontSize: TeksTeras.keterangan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
