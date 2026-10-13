import 'package:flutter/material.dart';

import '../data/sync/sync_otomatis.dart';
import '../features/dashboard/pages/dasbor_kasir_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/history/history_page.dart';
import '../features/profil/pages/profil_kasir_page.dart';
import '../features/sales/models/keranjang.dart';
import '../features/sales/sales_page.dart';
import '../features/shift/widgets/perlu_buka_shift.dart';
import '../shared/auth/session_manager.dart';
import '../shared/ui/bingkai_halaman.dart';
import '../shared/ui/nav_bawah_teras.dart';
import '../shared/ui/warna_teras.dart';
import '../shared/widgets/app_toast.dart';

/// Kerangka UI baru untuk kasir (desain): header + isi tab + nav bawah
/// Dashboard · Pengeluaran · Kasir (tengah) · Riwayat · Profil. Menggantikan
/// menu samping lama.
///
/// Keranjang dimiliki di sini supaya Dashboard (produk laris) dan halaman
/// Kasir memakai pesanan yang sama, dan isinya tidak hilang saat pindah tab.
class KerangkaKasir extends StatefulWidget {
  const KerangkaKasir({super.key});

  @override
  State<KerangkaKasir> createState() => _KerangkaKasirState();
}

class _KerangkaKasirState extends State<KerangkaKasir> {
  static const _iKasir = 2;

  static const _nav = <ItemNav>[
    ItemNav(
      ikon: Icons.grid_view_outlined,
      ikonAktif: Icons.grid_view_rounded,
      label: 'Dashboard',
    ),
    ItemNav(
      ikon: Icons.account_balance_wallet_outlined,
      ikonAktif: Icons.account_balance_wallet_rounded,
      label: 'Pengeluaran',
    ),
    ItemNav(
      ikon: Icons.point_of_sale_rounded,
      ikonAktif: Icons.point_of_sale_rounded,
      label: 'Kasir',
    ),
    ItemNav(
      ikon: Icons.receipt_long_outlined,
      ikonAktif: Icons.receipt_long_rounded,
      label: 'Riwayat',
    ),
    ItemNav(
      ikon: Icons.account_circle_outlined,
      ikonAktif: Icons.account_circle_rounded,
      label: 'Profil',
    ),
  ];

  final _keranjang = Keranjang();
  bool _keranjangTadinyaBerisi = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _keranjang.addListener(_keranjangBerubah);
    SessionManager.instance.sesiBerubah.addListener(_sesiBerubah);
    SessionManager.instance.shiftDitutupDariLuar.addListener(_shiftDitutup);
  }

  @override
  void dispose() {
    _keranjang
      ..removeListener(_keranjangBerubah)
      ..dispose();
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    SessionManager.instance.shiftDitutupDariLuar.removeListener(_shiftDitutup);
    // Kalau tidak dibersihkan, keluar dengan keranjang berisi membuat
    // penjadwal mengira pesanan masih disusun — dan sinkron otomatis berhenti
    // selamanya.
    SyncOtomatis.instance.sedangMenyusunPesanan = false;
    super.dispose();
  }

  /// Satu titik untuk SEMUA perubahan keranjang.
  void _keranjangBerubah() {
    final berisi = !_keranjang.isEmpty;
    // Sinkron otomatis ditunda selama pesanan disusun.
    SyncOtomatis.instance.sedangMenyusunPesanan = berisi;
    // Keranjang yang baru saja kosong adalah titik teraman untuk menyegarkan.
    // Tanpa ini sinkron yang tertunda bisa tertahan sepanjang jam ramai,
    // karena keranjang nyaris tidak pernah kosong lebih dari sesaat.
    if (_keranjangTadinyaBerisi && !berisi) {
      SyncOtomatis.instance.lanjutkanYangTertunda();
    }
    _keranjangTadinyaBerisi = berisi;
  }

  void _sesiBerubah() {
    if (mounted) setState(() {});
  }

  void _shiftDitutup() {
    final pesan = SessionManager.instance.shiftDitutupDariLuar.value;
    if (pesan == null || !mounted) return;
    SessionManager.instance.shiftDitutupDariLuar.value = null;
    AppToast.warning(context, pesan);
  }

  Widget _halaman(int tab) {
    final sm = SessionManager.instance;
    switch (tab) {
      case 0:
        return DasborKasirPage(keranjang: _keranjang);
      case 1:
        return const ExpensesPage();
      case _iKasir:
        if (!sm.hasPermission('create_transaction')) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Akun ini tidak punya izin Buat Transaksi. Minta pemilik '
                'mengaktifkannya di Hak Akses.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WarnaTeras.teksPudar),
              ),
            ),
          );
        }
        if (sm.currentSession?.shiftId == null) return const PerluBukaShift();
        return SalesPage(keranjang: _keranjang);
      case 3:
        return const HistoryPage();
      default:
        return const ProfilKasirPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftId = SessionManager.instance.currentSession?.shiftId;
    return PopScope(
      // Tombol kembali di tab lain → ke Dashboard; di Dashboard tidak
      // menutup aplikasi.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        backgroundColor: WarnaTeras.latar,
        body: SafeArea(
          bottom: false,
          child: BingkaiHalaman(
            judul: _nav[_tab].label,
            // Halaman dibuat ulang saat shift dibuka/ditutup: beberapa
            // halaman lama membaca shift sekali saat dibuat.
            child: KeyedSubtree(
              key: ValueKey('$_tab|$shiftId'),
              child: _halaman(_tab),
            ),
          ),
        ),
        bottomNavigationBar: NavBawahTeras(
          kiri: [_nav[0], _nav[1]],
          tengah: _nav[_iKasir],
          kanan: [_nav[3], _nav[4]],
          terpilih: _tab,
          onPilih: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}
