import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/inisial_akun.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/sakelar.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/simpan_lalu_kirim.dart';
import '../../auth/repositories/permission_repository.dart';
import '../models/ringkasan_kasir.dart';

/// Hak Akses satu kasir (desain): kartu akun + "Aktifkan semua", izin per
/// kelompok, lalu "Simpan Hak Akses".
///
/// Sakelar baru berlaku setelah disimpan. Kembali dengan perubahan yang
/// belum disimpan ditanya dulu, supaya tidak hilang diam-diam.
class HakAksesPage extends StatefulWidget {
  final User akun;

  /// Diisi test; aplikasi memakai basis data utama.
  final PermissionRepository? repo;

  const HakAksesPage({super.key, required this.akun, this.repo});

  @override
  State<HakAksesPage> createState() => _HakAksesPageState();
}

class _HakAksesPageState extends State<HakAksesPage> {
  late final _repo = widget.repo ?? PermissionRepository(db);
  List<(String, List<DefinisiIzin>)>? _kelompok;
  Map<String, bool> _awal = const {};
  Map<String, bool> _draf = {};
  var _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final semua = await _repo.getAllPermissions();
    final milik = await _repo.getUserPermissions(widget.akun.id);
    if (!mounted) return;
    final kelompok = kelompokIzinDari(semua);
    final awal = {
      for (final (_, isi) in kelompok)
        for (final d in isi) d.kode: milik[d.kode] ?? false,
    };
    setState(() {
      _kelompok = kelompok;
      _awal = awal;
      _draf = Map.of(awal);
    });
  }

  int get _aktif => _draf.values.where((v) => v).length;
  bool get _semuaAktif => _draf.isNotEmpty && _aktif == _draf.length;
  bool get _berubah => _draf.entries.any((e) => _awal[e.key] != e.value);

  void _ubahSemua() => setState(() {
    final nilai = !_semuaAktif;
    for (final k in _draf.keys) {
      _draf[k] = nilai;
    }
  });

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    final tersimpan = await simpanLaluKirim(
      context,
      simpan: () =>
          _repo.setUserPermissions(userId: widget.akun.id, permissions: _draf),
      pesanTerkirim: 'Hak akses ${widget.akun.username} diperbarui & terkirim',
      pesanTertunda: 'Tersimpan — berlaku di HP kasir setelah online',
    );
    if (!mounted) return;
    if (tersimpan) {
      _awal = Map.of(_draf);
      Navigator.pop(context);
    } else {
      setState(() => _menyimpan = false);
    }
  }

  Future<void> _kembali() async {
    final buang = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.edit_off_rounded,
      judul: 'Buang perubahan?',
      catatan: 'Hak akses yang diubah belum disimpan.',
      labelAksi: 'Buang',
    );
    if (buang && mounted) {
      setState(() => _awal = Map.of(_draf));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_berubah,
      onPopInvokedWithResult: (sudah, _) {
        if (!sudah) _kembali();
      },
      child: HalamanTurunan(
        judul: 'Hak Akses',
        child: _kelompok == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _kartuAkun(),
                  for (final (judul, isi) in _kelompok!) ...[
                    _judulKelompok(judul),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: WarnaTeras.kartu,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [for (final d in isi) _barisIzin(d)],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TombolLembar(
                    label: _menyimpan ? 'Menyimpan…' : 'Simpan Hak Akses',
                    latar: WarnaTeras.oranye,
                    warna: Colors.white,
                    tinggi: 50,
                    sudut: 12,
                    onPressed: _menyimpan ? null : _simpan,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _kartuAkun() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          InisialKasir(nama: widget.akun.username, ukuran: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.akun.username,
                  style: const TextStyle(
                    fontSize: TeksTeras.menu,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teks,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_aktif dari ${_draf.length} akses aktif',
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _ubahSemua,
            style: TextButton.styleFrom(foregroundColor: WarnaTeras.oranye),
            child: Text(
              _semuaAktif ? 'Nonaktifkan semua' : 'Aktifkan semua',
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _judulKelompok(String teks) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      teks,
      style: const TextStyle(
        fontSize: TeksTeras.kecil,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: WarnaTeras.teksSamar,
      ),
    ),
  );

  Widget _barisIzin(DefinisiIzin d) {
    final aktif = _draf[d.kode] ?? false;
    void ubah(bool v) => setState(() => _draf[d.kode] = v);
    return InkWell(
      onTap: () => ubah(!aktif),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: aktif ? WarnaTeras.oranyeMuda : WarnaTeras.latarAbu,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                d.ikon,
                size: 21,
                color: aktif ? WarnaTeras.oranye : WarnaTeras.ikonPasif,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.label,
                    style: const TextStyle(
                      fontSize: TeksTeras.menu,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.keterangan,
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Sakelar(nilai: aktif, onUbah: ubah, label: d.label),
          ],
        ),
      ),
    );
  }
}
