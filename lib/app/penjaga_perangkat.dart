import 'package:flutter/material.dart';

import '../data/perangkat/perangkat_repository.dart';
import '../features/auth/pages/login_page.dart';
import '../features/perangkat/pages/daftarkan_perangkat_page.dart';
import '../shared/ui/teks_teras.dart';
import '../shared/ui/tombol_lembar.dart';
import '../shared/ui/warna_teras.dart';

/// Menentukan layar mana yang berlaku menurut keadaan PERANGKAT ini, di
/// atas [child] (alur biasa: login, aplikasi).
///
/// | keadaan            | layar                                        |
/// |--------------------|----------------------------------------------|
/// | dicabut            | [PerangkatDicabutPage] — tanpa kolom kunci    |
/// | identitas dihapus  | Daftarkan Perangkat, dengan identitas baru    |
/// | belum terdaftar    | Daftarkan Perangkat, identitas yang ada       |
///
/// HP yang DICABUT sengaja tidak diberi kolom kunci (keputusan owner
/// 2026-10-24): dulu memasukkan kunci di sana langsung mengaktifkannya lagi,
/// jadi pencabutan hanya sekuat rahasianya kunci. Sekarang hanya pemilik
/// yang bisa memulihkannya, dari halaman Perangkat. HP yang DILUPAKAN
/// identitasnya sudah dihapus — ia kembali seperti HP baru dan boleh
/// mendaftar ulang dengan kunci.
///
/// Dipakai di dua tempat: di awal aplikasi (`main.dart`), dan oleh
/// `AppShell` sesudah login — dulu penjaganya hanya ada di awal, dan
/// halaman login menggantinya begitu masuk, sehingga HP yang dicabut tetap
/// bisa dipakai sampai aplikasinya dibuka ulang.
/// Rute ke halaman Login, SELALU di bawah [PenjagaPerangkat].
///
/// Halaman Login polos tidak menanggapi tanda dicabut: kasir yang Keluar
/// Akun lalu HP-nya dicabut owner bisa login lagi dan terus berjualan sampai
/// aplikasinya ditutup paksa (QA kedua S1). Semua jalan ke Login lewat sini.
Route<void> ruteMasuk() => MaterialPageRoute(
      builder: (_) => const PenjagaPerangkat(child: LoginPage()),
    );

class PenjagaPerangkat extends StatelessWidget {
  final Widget child;

  const PenjagaPerangkat({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = PerangkatRepository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        p.dicabut,
        p.identitasHilang,
        p.belumTerdaftar,
      ]),
      builder: (context, _) {
        if (p.dicabut.value) return const PerangkatDicabutPage();
        if (p.identitasHilang.value || p.belumTerdaftar.value) {
          return DaftarkanPerangkatPage(
            lengkapiSaja: !p.identitasHilang.value,
            // Penandanya berubah sendiri sesudah berhasil, dan layar ini
            // kembali ke [child] tanpa perlu pindah halaman.
            sesudahBerhasil: () async {},
          );
        }
        return child;
      },
    );
  }
}

/// "HP ini dicabut pemilik" — tanpa kolom kunci. Hanya pemilik yang bisa
/// memulihkannya dari halaman Perangkat di HP-nya.
class PerangkatDicabutPage extends StatefulWidget {
  /// Diisi test; aplikasi bertanya ke server. False = tidak tersambung.
  final Future<bool> Function()? periksa;

  const PerangkatDicabutPage({super.key, this.periksa});

  @override
  State<PerangkatDicabutPage> createState() => _PerangkatDicabutPageState();
}

class _PerangkatDicabutPageState extends State<PerangkatDicabutPage> {
  var _memeriksa = false;
  String? _catatan;

  Future<void> _periksa() async {
    if (_memeriksa) return;
    setState(() {
      _memeriksa = true;
      _catatan = null;
    });
    final tersambung = await (widget.periksa ??
        PerangkatRepository.instance.periksaKeServer)();
    if (!mounted) return;
    // Kalau sudah dipulihkan, penjaga di atas langsung mengganti layar ini.
    setState(() {
      _memeriksa = false;
      _catatan = !tersambung
          ? 'Tidak tersambung ke server. Periksa internet lalu coba lagi.'
          : 'Masih dicabut. Minta pemilik memulihkannya dulu.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarnaTeras.latar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: WarnaTeras.merahMuda,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phonelink_lock_rounded,
                    size: 44,
                    color: WarnaTeras.merah,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'HP ini dicabut pemilik',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'HP ini tidak bisa dipakai sampai pemilik memulihkannya dari '
                  'halaman Perangkat di HP owner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    height: 1.45,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: TombolLembar(
                    label: _memeriksa ? 'Memeriksa…' : 'Periksa lagi',
                    latar: WarnaTeras.oranye,
                    warna: Colors.white,
                    onPressed: _memeriksa ? null : _periksa,
                  ),
                ),
                if (_catatan != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _catatan!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
