import 'dart:async';

import 'package:flutter/material.dart';

import '../data/perangkat/perangkat_repository.dart';
import '../shared/auth/session_manager.dart';
import '../shared/widgets/app_toast.dart';
import 'kerangka_kasir.dart';
import 'kerangka_owner.dart';
import 'penjaga_perangkat.dart';

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
    for (final n in _penandaPerangkat) {
      n.addListener(_perangkatBerubah);
    }
    // Tandanya bisa SUDAH menyala sebelum login — tidak ada perubahan yang
    // terdengar, jadi diperiksa sekali di sini.
    WidgetsBinding.instance.addPostFrameCallback((_) => _perangkatBerubah());
  }

  List<ValueNotifier<bool>> get _penandaPerangkat {
    final p = PerangkatRepository.instance;
    return [p.dicabut, p.identitasHilang, p.belumTerdaftar];
  }

  var _sudahDialihkan = false;

  /// HP ini dicabut atau dilupakan pemilik selagi ada yang login.
  ///
  /// Dulu tidak ada yang menanggapinya: penjaga perangkat hanya hidup di
  /// halaman awal, dan halaman login menggantinya begitu masuk. HP yang
  /// dicabut tetap bisa dipakai berjualan sampai aplikasinya dibuka ulang —
  /// terbukti di emulator 2026-10-24. Sekarang sesinya diakhiri dan layar
  /// diserahkan ke [PenjagaPerangkat].
  void _perangkatBerubah() {
    if (!mounted || _sudahDialihkan) return;
    if (!_penandaPerangkat.any((n) => n.value)) return;
    _sudahDialihkan = true;
    unawaited(SessionManager.instance.clearSession());
    Navigator.of(context).pushAndRemoveUntil(ruteMasuk(), (route) => false);
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
    Navigator.of(context).pushAndRemoveUntil(ruteMasuk(), (route) => false);
  }

  void _sesiBerubah() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    SessionManager.instance.sesiDicabut.removeListener(_sesiDicabut);
    for (final n in _penandaPerangkat) {
      n.removeListener(_perangkatBerubah);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Di bawah penjaga juga: selama sesinya belum sempat dihapus, layar
    // kasir tidak boleh tampil sedetik pun di HP yang dicabut.
    return PenjagaPerangkat(child: Builder(builder: _kerangka));
  }

  Widget _kerangka(BuildContext context) {
    // Role, BUKAN permission — lihat test/arsitektur/role_bukan_permission_test.dart
    if (SessionManager.instance.isOwner) return const KerangkaOwner();
    return const KerangkaKasir();
  }
}
