import 'package:flutter/material.dart';

import '../features/dashboard/pages/dasbor_owner_page.dart';
import '../features/expenses/pages/pengeluaran_owner_page.dart';
import '../features/history/history_page.dart';
import '../features/products/pages/products_page.dart';
import '../features/profil/pages/profil_owner_page.dart';
import '../shared/ui/bingkai_halaman.dart';
import '../shared/ui/nav_bawah_teras.dart';
import '../shared/ui/warna_teras.dart';

/// Kerangka UI baru untuk owner: header + isi tab + nav bawah.
///
/// Owner tidak menjual, jadi tombol tengahnya Produk, bukan Kasir.
class KerangkaOwner extends StatefulWidget {
  const KerangkaOwner({super.key});

  @override
  State<KerangkaOwner> createState() => _KerangkaOwnerState();
}

class _KerangkaOwnerState extends State<KerangkaOwner> {
  int _tab = 0;

  static const _tabs = <({String judul, ItemNav nav, Widget halaman})>[
    (
      judul: 'Dashboard',
      nav: ItemNav(
        ikon: Icons.grid_view_outlined,
        ikonAktif: Icons.grid_view_rounded,
        label: 'Dashboard',
      ),
      halaman: DasborOwnerPage(),
    ),
    (
      judul: 'Pengeluaran',
      nav: ItemNav(
        ikon: Icons.account_balance_wallet_outlined,
        ikonAktif: Icons.account_balance_wallet_rounded,
        label: 'Pengeluaran',
      ),
      halaman: PengeluaranOwnerPage(),
    ),
    (
      judul: 'Produk',
      nav: ItemNav(
        ikon: Icons.shopping_basket_rounded,
        ikonAktif: Icons.shopping_basket_rounded,
        label: 'Produk',
      ),
      halaman: ProductsPage(),
    ),
    (
      judul: 'Riwayat',
      nav: ItemNav(
        ikon: Icons.receipt_long_outlined,
        ikonAktif: Icons.receipt_long_rounded,
        label: 'Riwayat',
      ),
      halaman: HistoryPage(),
    ),
    (
      judul: 'Profil',
      nav: ItemNav(
        ikon: Icons.account_circle_outlined,
        ikonAktif: Icons.account_circle_rounded,
        label: 'Profil',
      ),
      halaman: ProfilOwnerPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_tab];
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
          child: BingkaiHalaman(judul: tab.judul, child: tab.halaman),
        ),
        bottomNavigationBar: NavBawahTeras(
          kiri: [_tabs[0].nav, _tabs[1].nav],
          tengah: _tabs[2].nav,
          kanan: [_tabs[3].nav, _tabs[4].nav],
          terpilih: _tab,
          onPilih: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}
