import 'package:flutter/material.dart';

import '../features/auth/pages/login_page.dart';
import '../shared/auth/session_manager.dart';
import '../shared/widgets/app_toast.dart';
import 'kerangka_kasir.dart';
import 'kerangka_owner.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<AppShellState> globalKey = GlobalKey<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    // Nama dan role bisa berubah dari server; kerangkanya ikut digambar
    // ulang tanpa harus keluar dan masuk lagi.
    SessionManager.instance.sesiBerubah.addListener(_sesiBerubah);
    SessionManager.instance.sesiDicabut.addListener(_sesiDicabut);
  }

  /// Sesi dicabut dari jarak jauh — pemilik menonaktifkan atau menghapus akun
  /// ini, dan sinkronisasi baru saja membawa kabarnya.
  ///
  /// Dipaksa keluar, bukan sekadar diberi peringatan: selama masih di dalam
  /// aplikasi, orang yang aksesnya sudah dicabut tetap bisa membuat transaksi.
  ///
  /// Keranjang yang sedang disusun ikut hilang. Itu disengaja — penonaktifan
  /// adalah tindakan sengaja dan jarang, dan menundanya sampai transaksi
  /// selesai membuka jendela di mana orang yang sudah dicabut masih berjualan.
  /// Kalau ternyata salah pencet, pemilik tinggal mengaktifkan lagi; yang
  /// hilang cuma input, bukan data yang sudah tersimpan.
  void _sesiDicabut() {
    final alasan = SessionManager.instance.sesiDicabut.value;
    if (alasan == null || !mounted) return;
    SessionManager.instance.tandaiPencabutanSudahDitangani();

    AppToast.warning(context, alasan);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _sesiBerubah() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    SessionManager.instance.sesiDicabut.removeListener(_sesiDicabut);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Role, BUKAN permission — lihat test/arsitektur/role_bukan_permission_test.dart
    if (SessionManager.instance.isOwner) return const KerangkaOwner();
    return const KerangkaKasir();
  }
}
