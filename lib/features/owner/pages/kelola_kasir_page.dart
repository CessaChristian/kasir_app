import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_tambah.dart';
import '../../../shared/ui/warna_teras.dart';
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

  Future<void> _tambah() async {
    if (!await tampilkanTambahKasir(context, _repo) || !mounted) return;
    // Akun baru HANYA ada di HP ini sampai terkirim; kasirnya belum bisa
    // login sama sekali sebelum itu.
    await kirimSekarang(
      context,
      pesanTerkirim: 'Kasir ditambahkan & terkirim',
      pesanTertunda: 'Tersimpan — kasir bisa login setelah HP-nya online',
    );
  }

  /// Menonaktifkan ditanya dulu (akibatnya besar: akses langsung dicabut);
  /// mengaktifkan kembali langsung (desain).
  Future<void> _ubahAktif(User akun, bool aktif) async {
    if (!aktif) {
      final yakin = await tampilkanLembarKonfirmasi(
        context,
        ikon: Icons.person_off_rounded,
        judul: 'Nonaktifkan ${akun.username}?',
        catatan: 'Kasir tidak bisa login sampai akun diaktifkan lagi.',
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
    if (!await tampilkanUbahUsername(context, _repo, akun) || !mounted) return;
    await kirimSekarang(
      context,
      pesanTerkirim: 'Username diganti & terkirim',
      pesanTertunda:
          'Tersimpan — username baru berlaku di HP lain setelah online',
    );
  }

  Future<void> _resetPin(User akun) async {
    if (!await tampilkanResetPin(context, _repo, akun) || !mounted) return;
    // PIN baru HANYA ada di HP ini sampai terkirim: kasirnya terkunci —
    // PIN lama sudah tidak berlaku di sini, PIN baru belum sampai.
    await kirimSekarang(
      context,
      pesanTerkirim: 'PIN ${akun.username} diubah & terkirim',
      pesanTertunda: 'Tersimpan — PIN baru berlaku di HP kasir setelah online',
    );
  }

  void _hakAkses(User akun) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => HakAksesPage(akun: akun, repo: widget.repoIzin),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Kelola Kasir',
      child: StreamBuilder<List<RingkasanKasir>>(
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
                        onUbahAktif: (v) => _ubahAktif(r.akun, v),
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
                child: TombolTambah(
                  tooltip: 'Tambah akun kasir',
                  onTap: _tambah,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
