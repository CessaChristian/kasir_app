import 'package:flutter/material.dart';

import '../data/sync/sync_otomatis.dart';
import '../features/dashboard/pages/dasbor_kasir_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/history/history_page.dart';
import '../features/open_bill/sheets/lembar_open_bill.dart';
import '../features/open_bill/widgets/tombol_open_bill.dart';
import '../features/profil/pages/profil_kasir_page.dart';
import '../features/sales/models/keranjang.dart';
import '../features/sales/models/simpanan_keranjang.dart';
import '../features/sales/sales_page.dart';
import '../features/sales/widgets/tombol_keranjang.dart';
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
    _pulihkanKeranjang();
    SessionManager.instance.sesiBerubah.addListener(_sesiBerubah);
    SessionManager.instance.shiftDitutupDariLuar.addListener(_shiftDitutup);
    SessionManager.instance.shiftDigabung.addListener(_shiftDigabung);
  }

  @override
  void dispose() {
    _keranjang
      ..removeListener(_keranjangBerubah)
      ..dispose();
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    SessionManager.instance.shiftDitutupDariLuar.removeListener(_shiftDitutup);
    SessionManager.instance.shiftDigabung.removeListener(_shiftDigabung);
    // Kalau tidak dibersihkan, keluar dengan keranjang berisi membuat
    // penjadwal mengira pesanan masih disusun — dan sinkron otomatis berhenti
    // selamanya.
    SyncOtomatis.instance.sedangMenyusunPesanan = false;
    super.dispose();
  }

  /// Pesanan yang tertinggal waktu aplikasinya dimatikan (tes alur 10 Nov).
  Future<void> _pulihkanKeranjang() async {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) {
      _pemulihanSelesai = true;
      return;
    }
    final ada = await SimpananKeranjang.pulihkan(
      _keranjang,
      userId: sesi.userId,
      shiftId: sesi.shiftId,
    );
    _pemulihanSelesai = true;
    if (ada && mounted) AppToast.info(context, 'Pesanan sebelumnya dipulihkan');
  }

  /// Simpanan tidak ditulis sebelum pemulihan selesai: keranjang kosong saat
  /// halaman baru dibuka akan menghapus simpanan yang belum sempat dibaca.
  var _pemulihanSelesai = false;

  /// Satu titik untuk SEMUA perubahan keranjang.
  void _keranjangBerubah() {
    final sesi = SessionManager.instance.currentSession;
    if (_pemulihanSelesai && sesi != null) {
      SimpananKeranjang.simpan(
        _keranjang,
        userId: sesi.userId,
        shiftId: sesi.shiftId,
      );
    }
    final berisi = !_keranjang.isEmpty;
    // Sinkron otomatis ditunda selama pesanan disusun.
    _perbaruiPenahan();
    // Keranjang yang baru saja kosong adalah titik teraman untuk menyegarkan.
    // Tanpa ini sinkron yang tertunda bisa tertahan sepanjang jam ramai,
    // karena keranjang nyaris tidak pernah kosong lebih dari sesaat.
    if (_keranjangTadinyaBerisi && !berisi) {
      SyncOtomatis.instance.lanjutkanYangTertunda();
    }
    _keranjangTadinyaBerisi = berisi;
  }

  /// Sinkron otomatis ditahan hanya selama ada pesanan yang BISA dibayar:
  /// keranjang berisi DAN shift masih dipegang. Shift yang ditutup dari HP
  /// lain melepas shift dari sesi, tapi keranjangnya tetap berisi — dulu
  /// sinkron ikut tertahan sampai kasir mengosongkannya sendiri, jadi data
  /// HP ini tidak terkirim (audit 6 Nov nomor 47).
  void _perbaruiPenahan() {
    final tadi = SyncOtomatis.instance.sedangMenyusunPesanan;
    final tahan = !_keranjang.isEmpty &&
        SessionManager.instance.currentSession?.shiftId != null;
    SyncOtomatis.instance.sedangMenyusunPesanan = tahan;
    if (tadi && !tahan && !_keranjang.isEmpty) {
      SyncOtomatis.instance.lanjutkanYangTertunda();
    }
  }

  void _sesiBerubah() {
    _perbaruiPenahan();
    if (mounted) setState(() {});
  }

  void _shiftDitutup() {
    final pesan = SessionManager.instance.shiftDitutupDariLuar.value;
    if (pesan == null || !mounted) return;
    SessionManager.instance.shiftDitutupDariLuar.value = null;
    AppToast.warning(context, pesan);
  }

  void _shiftDigabung() {
    final pesan = SessionManager.instance.shiftDigabung.value;
    if (pesan == null || !mounted) return;
    SessionManager.instance.shiftDigabung.value = null;
    AppToast.info(context, pesan);
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
        return ProfilKasirPage(
          onLihatOpenBill: () => bukaDaftarOpenBill(context, _keranjang),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftId = SessionManager.instance.currentSession?.shiftId;
    final bolehJual = SessionManager.instance.hasPermission(
      'create_transaction',
    );
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
            aksi: [
              if (_tab == _iKasir && shiftId != null && bolehJual)
                TombolKeranjang(keranjang: _keranjang),
              // Desain: ikon Open Bill di Dashboard dan Kasir.
              if ((_tab == 0 || _tab == _iKasir) && bolehJual)
                TombolOpenBill(keranjang: _keranjang, shiftId: shiftId),
            ],
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
