import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/tombol_tambah.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/simpan_lalu_kirim.dart';
import '../../auth/repositories/permission_repository.dart';
import '../models/ringkasan_kasir.dart';
import '../repositories/cashier_repository.dart';
import '../widgets/kartu_kasir.dart';
import '../widgets/lembar_kasir.dart';
import 'hak_akses_page.dart';

/// Kelola Kasir (desain): kartu per kasir dengan sakelar aktif, ⋮, Hak Akses,
/// dan Reset PIN; tombol + untuk akun baru.
///
/// Hak PATEN owner — hanya terjangkau dari Profil owner, dan
/// [CashierRepository] menolak perubahan dari akun lain.
///
/// WAJIB online (keputusan owner 2026-10-07): tanpa server, halaman hanya
/// menampilkan "butuh internet". Setiap aksi memeriksa koneksi lagi sebelum
/// lembarnya dibuka; repositori menegakkannya sekali lagi saat menyimpan.
///
/// Setiap perubahan langsung dikirim (`kirimSekarang`/`simpanLaluKirim`):
/// akibatnya dirasakan di HP kasir, dan pesannya harus jujur soal sudah
/// sampai atau belum.
class KelolaKasirPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final CashierRepository? repo;
  final PermissionRepository? repoIzin;

  const KelolaKasirPage({super.key, this.repo, this.repoIzin});

  @override
  State<KelolaKasirPage> createState() => _KelolaKasirPageState();
}

class _KelolaKasirPageState extends State<KelolaKasirPage> {
  late final _repo = widget.repo ?? CashierRepository(db);
  late final _aliran = _repo.watchDaftarKasir();

  /// null = sedang memeriksa koneksi; false = tanpa internet.
  bool? _terhubung;

  @override
  void initState() {
    super.initState();
    _periksaKoneksi();
  }

  Future<void> _periksaKoneksi() async {
    setState(() => _terhubung = null);
    final ok = await _repo.terhubung();
    if (mounted) setState(() => _terhubung = ok);
  }

  /// Dipanggil sebelum setiap aksi. Tanpa internet: pesan, dan halaman
  /// kembali ke layar "butuh internet".
  Future<bool> _wajibOnline() async {
    if (await _repo.terhubung()) return true;
    if (mounted) {
      setState(() => _terhubung = false);
      AppToast.error(context, pesanButuhInternet);
    }
    return false;
  }

  Future<void> _tambah() async {
    if (!await _wajibOnline() || !mounted) return;
    if (!await tampilkanTambahKasir(context, _repo) || !mounted) return;
    // Akun baru HANYA ada di HP ini sampai terkirim; kasirnya belum bisa
    // login sama sekali sebelum itu.
    await kirimSekarang(
      context,
      pesanTerkirim: 'Kasir ditambahkan & terkirim',
      pesanTertunda: 'Tersimpan — kasir bisa login setelah HP-nya online',
    );
  }

  /// Menonaktifkan ditanya dulu (akibatnya besar: akses langsung dicabut,
  /// dan shift yang berjalan ikut diakhiri); mengaktifkan kembali langsung
  /// (desain).
  Future<void> _ubahAktif(RingkasanKasir r, bool aktif) async {
    final akun = r.akun;
    if (!await _wajibOnline() || !mounted) return;
    if (!aktif) {
      final mulai = r.mulaiShiftBerjalan;
      final yakin = await tampilkanLembarKonfirmasi(
        context,
        ikon: Icons.person_off_rounded,
        judul: 'Nonaktifkan ${akun.username}?',
        catatan: mulai == null
            ? 'Kasir tidak bisa login sampai akun diaktifkan lagi.'
            : 'Kasir tidak bisa login sampai akun diaktifkan lagi. '
                  'Shift-nya yang berjalan sejak '
                  '${DateFormat('HH:mm').format(mulai.toLocal())} '
                  'ikut diakhiri.',
        labelAksi: 'Nonaktifkan',
      );
      if (!yakin || !mounted) return;
    }
    await simpanLaluKirim(
      context,
      simpan: () => _repo.toggleCashierStatus(akun.id, aktif),
      // Menyebut HP kasir, bukan sekadar "berhasil": pencabutan akses baru
      // berlaku di sana.
      pesanTerkirim: aktif
          ? '${akun.username} diaktifkan & terkirim'
          : '${akun.username} dinonaktifkan — akses dicabut',
      pesanTertunda: aktif
          ? 'Tersimpan — berlaku di HP kasir setelah online'
          : 'Tersimpan — akses baru tercabut di HP kasir setelah online',
      pesanGagal: (e) => 'Gagal: $e',
    );
  }

  Future<void> _menu(User akun) async {
    if (!await tampilkanMenuAkun(context, akun) || !mounted) return;
    if (!await _wajibOnline() || !mounted) return;
    if (!await tampilkanUbahUsername(context, _repo, akun) || !mounted) return;
    await kirimSekarang(
      context,
      pesanTerkirim: 'Username diganti & terkirim',
      pesanTertunda:
          'Tersimpan — username baru berlaku di HP lain setelah online',
    );
  }

  Future<void> _resetPin(User akun) async {
    if (!await _wajibOnline() || !mounted) return;
    if (!await tampilkanResetPin(context, _repo, akun) || !mounted) return;
    // PIN baru HANYA ada di HP ini sampai terkirim: kasirnya terkunci —
    // PIN lama sudah tidak berlaku di sini, PIN baru belum sampai.
    await kirimSekarang(
      context,
      pesanTerkirim: 'PIN ${akun.username} diubah & terkirim',
      pesanTertunda: 'Tersimpan — PIN baru berlaku di HP kasir setelah online',
    );
  }

  Future<void> _hakAkses(User akun) async {
    if (!await _wajibOnline() || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HakAksesPage(
          akun: akun,
          repo: widget.repoIzin,
          cekKoneksi: _repo.terhubung,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Kelola Kasir',
      child: switch (_terhubung) {
        null => const Center(child: CircularProgressIndicator()),
        false => _butuhInternet(),
        true => _daftar(),
      },
    );
  }

  Widget _butuhInternet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: WarnaTeras.oranyeMuda,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 28,
                color: WarnaTeras.oranye,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Kelola Kasir butuh internet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TeksTeras.judulBagian,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Perubahan akun kasir harus langsung sampai ke server supaya '
              'tidak bentrok dengan HP lain.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                height: 1.4,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: TombolLembar(
                label: 'Coba lagi',
                ikon: Icons.refresh_rounded,
                latar: WarnaTeras.oranye,
                warna: Colors.white,
                onPressed: _periksaKoneksi,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daftar() {
    return StreamBuilder<List<RingkasanKasir>>(
      stream: _aliran,
      builder: (context, snap) {
        final daftar = snap.data;
        final sekarang = DateTime.now();
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (daftar == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (daftar.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Belum ada akun kasir',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  )
                else
                  for (final r in daftar) ...[
                    KartuKasir(
                      key: ValueKey(r.akun.id),
                      ringkasan: r,
                      sekarang: sekarang,
                      onUbahAktif: (v) => _ubahAktif(r, v),
                      onMenu: () => _menu(r.akun),
                      onHakAkses: () => _hakAkses(r.akun),
                      onResetPin: () => _resetPin(r.akun),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: TombolTambah(tooltip: 'Tambah akun kasir', onTap: _tambah),
            ),
          ],
        );
      },
    );
  }
}
