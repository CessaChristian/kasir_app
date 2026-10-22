import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_shell.dart';
import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/kerangka_masuk.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/sync_refresh.dart';
import '../../../utils/crypto_utils.dart';
import '../recovery/pages/owner_recovery_page.dart';
import '../repositories/auth_repository.dart';

/// Halaman Login (desain): username + PIN, galat sebaris di bawah PIN
/// berdampingan dengan "Lupa PIN Owner?".
class LoginPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final AuthRepository? repo;

  const LoginPage({super.key, this.repo});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _repo = widget.repo ?? AuthRepository(db);
  final _username = TextEditingController();
  final _pin = TextEditingController();

  var _memuat = false;
  String? _galat;

  @override
  void initState() {
    super.initState();
    // Sesi yang berakhir saat aplikasi dibuka (mis. 15 menit diam) belum
    // punya layar yang mengumumkannya — AppShell belum pernah tampil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alasan = SessionManager.instance.sesiDicabut.value;
      if (alasan == null || !mounted) return;
      SessionManager.instance.tandaiPencabutanSudahDitangani();
      AppToast.warning(context, alasan);
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _hapusGalat(String _) {
    if (_galat != null) setState(() => _galat = null);
  }

  String? _periksa() {
    if (_username.text.trim().isEmpty) return 'Username wajib diisi';
    if (_pin.text.isEmpty) return 'PIN wajib diisi';
    if (_pin.text.length != CryptoUtils.pinLength) {
      return 'PIN harus ${CryptoUtils.pinLength} digit';
    }
    return null;
  }

  Future<void> _masuk() async {
    // Tombol Masuk mati selama memeriksa, tapi Enter di keyboard tidak.
    if (_memuat) return;
    final galat = _periksa();
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });

    try {
      final sesi = await _repo.login(
        username: _username.text.trim(),
        pin: _pin.text,
      );
      if (!mounted) return;
      if (sesi == null) {
        setState(() {
          _memuat = false;
          _galat = 'Username atau PIN salah';
        });
        return;
      }

      await SessionManager.instance.setSession(sesi);
      // Login yang melanjutkan shift: server langsung tahu perangkat ini ikut
      // memegangnya. Sengaja tidak ditunggu — login tidak boleh menunggu
      // jaringan.
      if (sesi.shiftId != null) unawaited(_repo.laporShift(sesi.shiftId));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AppShell(key: AppShell.globalKey)),
      );
    } on StateError catch (e) {
      // Akun dinonaktifkan/dihapus, terlalu banyak percobaan, dsb.
      if (!mounted) return;
      setState(() {
        _memuat = false;
        _galat = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memuat = false;
        _galat = 'Terjadi kesalahan: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final galat = _galat != null;
    return KerangkaMasuk(
      judul: 'Login to Access Your',
      // Halaman login pun perlu bisa disegarkan.
      //
      // Kasir yang akunnya baru diaktifkan kembali pemilik tidak bisa masuk
      // sampai kabarnya sampai ke HP ini — dan di layar login tidak ada satu
      // pun jalan untuk memintanya. Menunggu putaran otomatis bisa sampai
      // lima menit, sementara orangnya berdiri di depan kasir mencoba
      // berulang kali dan gagal terus tanpa tahu kenapa.
      bungkus: (gulir) => SyncRefresh(child: gulir),
      isi: [
        const LabelMasuk('Username', atas: 36),
        KolomMasuk(
          controller: _username,
          ikon: Icons.person_rounded,
          petunjuk: 'Masukkan username',
          galat: galat,
          textInputAction: TextInputAction.next,
          onChanged: _hapusGalat,
        ),
        const LabelMasuk('PIN'),
        KolomMasuk(
          controller: _pin,
          ikon: Icons.lock_rounded,
          petunjuk: '• • • • • •',
          rahasia: true,
          galat: galat,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(CryptoUtils.pinLength),
          ],
          onChanged: _hapusGalat,
          onSubmitted: (_) => _masuk(),
        ),
        const JarakMasuk(16),
        BarisGalatMasuk(
          galat: _galat,
          kanan: GestureDetector(
            onTap: () {
              setState(() => _galat = null);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OwnerRecoveryPage(repo: _repo),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'Lupa PIN Owner?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.oranyeCerah,
                ),
              ),
            ),
          ),
        ),
        const JarakMasuk(36),
        TombolMasuk(
          label: _memuat ? 'Memeriksa…' : 'Masuk',
          onPressed: _memuat ? null : _masuk,
        ),
      ],
    );
  }
}
