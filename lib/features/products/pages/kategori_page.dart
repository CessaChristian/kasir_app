import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/db.dart';
import '../../../shared/constants/category_icons.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/simpan_lalu_kirim.dart';
import '../repositories/product_repository.dart';

/// Panjang maksimal nama kategori (desain).
const panjangNamaKategori = 20;

/// Halaman Kategori (desain): tambah kategori, sembunyikan dari Kasir, hapus.
///
/// Semua aksi masuk DRAF dulu dan baru berlaku saat "Simpan Perubahan"
/// (keputusan owner 2026-10-13). Kembali dengan draf yang belum disimpan
/// ditanya "Buang perubahan?".
///
/// Tidak wajib online: kategori tidak menyangkut login atau keamanan.
/// Perubahannya tersimpan di HP dan terkirim begitu tersambung.
class KategoriPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final ProductRepository? repo;

  const KategoriPage({super.key, this.repo});

  @override
  State<KategoriPage> createState() => _KategoriPageState();
}

/// Satu kategori di draf. [id] null = kategori baru yang belum disimpan.
class _Draf {
  final String? id;
  final String nama;
  final int? ikon;
  bool tampil;

  _Draf({this.id, required this.nama, this.ikon, this.tampil = true});
}

class _KategoriPageState extends State<KategoriPage> {
  late final _repo = widget.repo ?? ProductRepository(db);
  final _nama = TextEditingController();

  /// Keadaan tersimpan: id -> tampil di Kasir. Null selama memuat.
  Map<String, bool>? _awal;
  List<_Draf> _draf = [];

  /// Jumlah produk per id kategori.
  Map<String, int> _produkPer = const {};

  /// Produk yang tidak punya kategori (termasuk yang kategorinya sudah tidak
  /// ada).
  int _produkTanpa = 0;

  IconData _ikon = kIkonPilihanKategori.first;
  String _galat = '';
  var _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final (kategori, produk) = await (
      _repo.watchCategories().first,
      _repo.watchProducts().first,
    ).wait;
    if (!mounted) return;
    final ada = {for (final c in kategori) c.id};
    final per = <String, int>{};
    var tanpa = 0;
    for (final p in produk) {
      final k = p.categoryId;
      if (k != null && ada.contains(k)) {
        per[k] = (per[k] ?? 0) + 1;
      } else {
        tanpa++;
      }
    }
    setState(() {
      _awal = {for (final c in kategori) c.id: c.tampilDiKasir};
      _draf = [
        for (final c in kategori)
          _Draf(
            id: c.id,
            nama: c.name,
            ikon: c.iconCodepoint,
            tampil: c.tampilDiKasir,
          ),
      ];
      _produkPer = per;
      _produkTanpa = tanpa;
    });
  }

  Iterable<String> get _dihapus {
    final masih = {for (final d in _draf) d.id};
    return _awal!.keys.where((id) => !masih.contains(id));
  }

  bool get _berubah =>
      _awal != null &&
      (_draf.any((d) => d.id == null || _awal![d.id] != d.tampil) ||
          _dihapus.isNotEmpty);

  int _jumlahProduk(_Draf d) => d.id == null ? 0 : _produkPer[d.id] ?? 0;

  /// Termasuk produk dari kategori yang dihapus di draf — angkanya langsung
  /// menunjukkan akibat penghapusan sebelum disimpan.
  int get _jumlahTanpa =>
      _produkTanpa + _dihapus.fold(0, (n, id) => n + (_produkPer[id] ?? 0));

  void _tambah() {
    final nama = _nama.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nama.isEmpty) {
      setState(() => _galat = 'Nama kategori wajib diisi');
      return;
    }
    final kecil = nama.toLowerCase();
    if (kecil == namaTanpaKategori.toLowerCase() ||
        _draf.any((d) => d.nama.toLowerCase() == kecil)) {
      setState(() => _galat = 'Kategori sudah ada');
      return;
    }
    setState(() {
      _draf = [..._draf, _Draf(nama: nama, ikon: _ikon.codePoint)]
        ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
      _nama.clear();
      _galat = '';
    });
  }

  Future<void> _hapus(_Draf d) async {
    final n = _jumlahProduk(d);
    final ya = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.delete_rounded,
      judul: 'Hapus kategori ${d.nama}?',
      catatan: n > 0
          ? '$n produk di kategori ini akan pindah ke $namaTanpaKategori.'
          : 'Kategori ini akan dihapus dari daftar.',
      labelAksi: 'Hapus',
    );
    if (ya && mounted) setState(() => _draf = [..._draf]..remove(d));
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    final awal = _awal!;
    final tersimpan = await simpanLaluKirim(
      context,
      simpan: () => _repo.simpanKategori(
        tambah: [
          for (final d in _draf)
            if (d.id == null) (nama: d.nama, ikon: d.ikon),
        ],
        tampil: {
          for (final d in _draf)
            if (d.id != null && awal[d.id] != d.tampil) d.id!: d.tampil,
        },
        hapus: _dihapus.toList(),
      ),
      pesanTerkirim: 'Kategori disimpan · langsung berlaku di Kasir',
      pesanTertunda: 'Kategori disimpan · berlaku di HP lain setelah online',
      pesanGagal: (e) {
        final pesan = e is StateError ? e.message : '$e';
        return pesan.startsWith('Permission required')
            ? 'Akun ini tidak punya izin Kelola Kategori'
            : 'Gagal menyimpan: $pesan';
      },
    );
    if (!mounted) return;
    // Dimuat ulang dari database: lencana "Baru" hilang dan draf kembali
    // sama dengan yang tersimpan.
    if (tersimpan) await _muat();
    if (mounted) setState(() => _menyimpan = false);
  }

  Future<void> _kembali() async {
    final buang = await tanyaBuangPerubahan(
      context,
      catatan: 'Perubahan kategori yang belum disimpan akan hilang.',
    );
    if (buang && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_berubah,
      onPopInvokedWithResult: (sudah, _) {
        if (!sudah) _kembali();
      },
      child: HalamanTurunan(
        judul: 'Kategori',
        child: _awal == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [_kartuTambah(), _judulDaftar(), _daftar()],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: TombolLembar(
                      label: _menyimpan
                          ? 'Menyimpan…'
                          : _berubah
                          ? 'Simpan Perubahan'
                          : 'Tidak ada perubahan',
                      ikon: Icons.save_rounded,
                      latar: WarnaTeras.oranye,
                      warna: Colors.white,
                      latarNonaktif: const Color(0xFFE2E0DE),
                      warnaNonaktif: const Color(0xFFA8A29C),
                      tinggi: 46,
                      sudut: 12,
                      onPressed: _berubah && !_menyimpan ? _simpan : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _kartuTambah() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tambah Kategori',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teks,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ikon in kIkonPilihanKategori) _pilihanIkon(ikon),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE6DED6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(_ikon, size: 20, color: WarnaTeras.oranye),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _nama,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              panjangNamaKategori,
                            ),
                          ],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            if (_galat.isNotEmpty) setState(() => _galat = '');
                          },
                          onSubmitted: (_) => _tambah(),
                          style: const TextStyle(
                            fontSize: TeksTeras.biasa,
                            color: WarnaTeras.teks,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Nama kategori baru',
                            hintStyle: TextStyle(color: Color(0xFFB5ADA6)),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: WarnaTeras.oranye,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _tambah,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: Colors.white,
                      semanticLabel: 'Tambah kategori',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 14,
            child: Text(
              _galat,
              style: const TextStyle(fontSize: 12, color: WarnaTeras.merah),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pilihanIkon(IconData ikon) {
    final dipilih = ikon == _ikon;
    return Material(
      color: dipilih ? WarnaTeras.oranye : WarnaTeras.latarAbu,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _ikon = ikon),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            ikon,
            size: 19,
            color: dipilih ? Colors.white : WarnaTeras.teksPudar,
          ),
        ),
      ),
    );
  }

  Widget _judulDaftar() {
    final tampil = _draf.where((d) => d.tampil).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'DAFTAR KATEGORI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: WarnaTeras.teksSamar,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$tampil dari ${_draf.length} tampil di Kasir',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: WarnaTeras.teksPudar),
            ),
          ),
        ],
      ),
    );
  }

  Widget _daftar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [for (final d in _draf) _baris(d), _barisTanpaKategori()],
      ),
    );
  }

  Widget _baris(_Draf d) {
    final n = _jumlahProduk(d);
    return _BarisKategori(
      ikon: categoryIconFromCodepoint(d.ikon),
      nama: d.nama,
      redup: !d.tampil,
      baru: d.id == null,
      keterangan: '$n produk${d.tampil ? '' : ' · disembunyikan di Kasir'}',
      warnaKeterangan: d.tampil ? WarnaTeras.teksPudar : WarnaTeras.merah,
      ujung: [
        _TombolKecil(
          ikon: d.tampil
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          tooltip: d.tampil ? 'Sembunyikan di Kasir' : 'Tampilkan di Kasir',
          latar: d.tampil ? WarnaTeras.oranyeMuda : WarnaTeras.latarAbu,
          warna: d.tampil ? WarnaTeras.oranye : WarnaTeras.teksSamar,
          onTap: () => setState(() => d.tampil = !d.tampil),
        ),
        const SizedBox(width: 10),
        _TombolKecil(
          ikon: Icons.delete_rounded,
          tooltip: 'Hapus ${d.nama}',
          latar: WarnaTeras.merahMuda,
          warna: WarnaTeras.merah,
          onTap: () => _hapus(d),
        ),
      ],
    );
  }

  Widget _barisTanpaKategori() {
    return _BarisKategori(
      ikon: kIkonTanpaKategori,
      nama: namaTanpaKategori,
      redup: true,
      keterangan: '$_jumlahTanpa produk',
      warnaKeterangan: WarnaTeras.teksPudar,
      ujung: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WarnaTeras.latarAbu,
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text(
            'Bawaan',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teksPudar,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarisKategori extends StatelessWidget {
  final IconData ikon;
  final String nama;

  /// Ikon abu-abu (disembunyikan, atau baris bawaan Tanpa Kategori).
  final bool redup;
  final bool baru;
  final String keterangan;
  final Color warnaKeterangan;
  final List<Widget> ujung;

  const _BarisKategori({
    required this.ikon,
    required this.nama,
    required this.redup,
    this.baru = false,
    required this.keterangan,
    required this.warnaKeterangan,
    required this.ujung,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: redup ? WarnaTeras.latarAbu : WarnaTeras.oranyeMuda,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              ikon,
              size: 19,
              color: redup ? WarnaTeras.teksSamar : WarnaTeras.oranye,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.teks,
                        ),
                      ),
                    ),
                    if (baru) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: WarnaTeras.hijauMuda,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Baru',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: WarnaTeras.hijau,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  keterangan,
                  style: TextStyle(fontSize: 11, color: warnaKeterangan),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ...ujung,
        ],
      ),
    );
  }
}

class _TombolKecil extends StatelessWidget {
  final IconData ikon;
  final String tooltip;
  final Color latar;
  final Color warna;
  final VoidCallback onTap;

  const _TombolKecil({
    required this.ikon,
    required this.tooltip,
    required this.latar,
    required this.warna,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(ikon, size: 19, color: warna),
          ),
        ),
      ),
    );
  }
}
