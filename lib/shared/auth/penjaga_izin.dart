import 'package:flutter/material.dart';

import '../widgets/app_toast.dart';
import 'session_manager.dart';

/// Halaman yang dibuka dengan izin [izin] (Produk, Kategori, Laporan) dan
/// ditutup sendiri begitu izinnya dicabut owner selagi terbuka.
///
/// Menu di Profil memang langsung hilang, tapi halaman yang SUDAH terbuka
/// dulu tetap bisa dipakai sampai ditutup kasir sendiri (review C1/C2,
/// keputusan owner 2026-11-04: berlaku untuk semua halaman berizin).
class PenjagaIzin extends StatefulWidget {
  final String izin;

  /// Nama fitur di pesan, mis. "Laporan".
  final String namaFitur;
  final Widget child;

  const PenjagaIzin({
    super.key,
    required this.izin,
    required this.namaFitur,
    required this.child,
  });

  @override
  State<PenjagaIzin> createState() => _PenjagaIzinState();
}

class _PenjagaIzinState extends State<PenjagaIzin> {
  var _ditutup = false;

  @override
  void initState() {
    super.initState();
    SessionManager.instance.sesiBerubah.addListener(_periksa);
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_periksa);
    super.dispose();
  }

  void _periksa() {
    final sm = SessionManager.instance;
    // Tanpa sesi = sedang keluar; halaman login yang mengambil alih.
    if (_ditutup || !mounted || !sm.isLoggedIn) return;
    if (sm.hasPermission(widget.izin)) return;
    _ditutup = true;
    AppToast.warning(
      context,
      'Izin ${widget.namaFitur} dicabut owner. Halaman ditutup.',
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
