import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../data/sync/sync_otomatis.dart';
import '../../data/sync/sync_service.dart';
import '../../shared/constants/category_icons.dart';
import '../../shared/ui/warna_teras.dart';
import '../../shared/widgets/sync_refresh.dart';
import '../../utils/currency_formatter.dart';
import '../products/repositories/product_repository.dart';
import '../products/widgets/baris_produk.dart';
import 'models/keranjang.dart';
import 'models/pilihan_produk.dart';
import 'models/saring_kategori.dart';
import 'sheets/pilihan_produk_sheet.dart';

/// "Sinkron terakhir 14:32" di bawah kotak cari.
String labelSinkronTerakhir(DateTime? waktu, DateTime sekarang) {
  if (waktu == null) return 'Belum pernah sinkron';
  final jam = DateFormat('HH:mm').format(waktu);
  final hariIni =
      waktu.year == sekarang.year &&
      waktu.month == sekarang.month &&
      waktu.day == sekarang.day;
  return hariIni
      ? 'Sinkron terakhir $jam'
      : 'Sinkron terakhir ${DateFormat('d MMM', 'id_ID').format(waktu)} $jam';
}

/// Halaman KASIR (desain): cari produk · Cari Berdasarkan Kategori (kisi 4
/// kolom) · kisi produk 2 kolom. Keranjang dibuka dari ikon di header
/// (`TombolKeranjang`), dimiliki kerangka kasir dan dipakai bersama
/// Dashboard.
class SalesPage extends StatefulWidget {
  final Keranjang keranjang;

  /// Diisi test; aplikasi memakai basis data utama.
  final ProductRepository? repo;

  const SalesPage({super.key, required this.keranjang, this.repo});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late final _productRepo = widget.repo ?? ProductRepository(db);
  late final _aliranProduk = _productRepo.watchProducts();
  final _cari = TextEditingController();
  final Set<String> _sedangDitambah = {};

  /// null = semua; [pilihanTanpaKategori]; atau id kategori.
  String? _pilihan;

  /// Semua kategori (termasuk yang disembunyikan) — penyaring produk perlu
  /// tahu kategori mana yang masih ada.
  List<Category> _kategori = const [];
  late final StreamSubscription<List<Category>> _langgananKategori;

  Keranjang get _keranjang => widget.keranjang;

  @override
  void initState() {
    super.initState();
    // Membuka halaman kasir adalah momen alami untuk memastikan harganya
    // terbaru — jeda minimum di dalam penjadwal yang mencegah ini menembak
    // berulang kali saat berpindah-pindah halaman.
    SyncOtomatis.instance.picu('halaman kasir dibuka');
    _keranjang.addListener(_segarkan);
    _langgananKategori = _productRepo.watchCategories().listen((k) {
      if (mounted) setState(() => _kategori = k);
    });
  }

  @override
  void dispose() {
    _langgananKategori.cancel();
    _keranjang.removeListener(_segarkan);
    _cari.dispose();
    super.dispose();
  }

  /// Keranjang berubah (dari sini, lembar Keranjang, atau Dashboard).
  /// Penundaan sinkron selama pesanan disusun diurus kerangka kasir.
  void _segarkan() {
    if (mounted) setState(() {});
  }

  Future<void> _tambah(Product p) async {
    // Kunci per produk: cegah ketuk ganda sebelum lembar varian terbuka.
    if (!_sedangDitambah.add(p.id)) return;
    try {
      // Produk yang punya pilihan ditanyakan SETIAP kali diketuk: pilihan
      // berbeda jadi baris baru. Menambah jumlah dengan pilihan yang sama
      // dilakukan lewat tombol + di keranjang.
      String? catatan;
      if (kelompokUntuk(p).isNotEmpty) {
        final hasil = await tanyaPilihanProduk(context, p);
        if (hasil == null) return; // lembar ditutup = batal
        catatan = catatanItem(hasil);
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _keranjang.tambah(
        idProduk: p.id,
        nama: p.name,
        harga: p.price,
        catatan: catatan,
      );
    } finally {
      _sedangDitambah.remove(p.id);
    }
  }

  void _pilih(String id) =>
      setState(() => _pilihan = _pilihan == id ? null : id);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _aliranProduk,
      builder: (context, snap) {
        final semua = snap.data ?? const <Product>[];
        final pilihan = pilihanEfektif(_kategori, _pilihan);
        var produk = saringPerKategori(semua, _kategori, pilihan);
        final kata = _cari.text.trim().toLowerCase();
        if (kata.isNotEmpty) {
          produk = [
            for (final p in produk)
              if (p.name.toLowerCase().contains(kata)) p,
          ];
        }
        return SyncRefresh(
          child: ListView(
            // Tanpa ini, gerakan menarik tidak terbaca saat produknya sedikit
            // dan layar belum penuh.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _kotakCari(),
              const SizedBox(height: 10),
              _sinkronTerakhir(),
              const Padding(
                padding: EdgeInsets.only(top: 18, bottom: 12),
                child: Text(
                  'Cari Berdasarkan Kategori',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
              ),
              _kisiKategori(adaProdukTanpaKategori(semua, _kategori), pilihan),
              if (pilihan != null) _barisFilter(pilihan, produk.length),
              const SizedBox(height: 14),
              if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (produk.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    semua.isEmpty
                        ? 'Belum ada produk'
                        : 'Produk tidak ditemukan',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                )
              else
                _kisiProduk(produk),
            ],
          ),
        );
      },
    );
  }

  Widget _kotakCari() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F3C230A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 24, color: WarnaTeras.oranye),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _cari,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 15, color: WarnaTeras.teks),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Cari produk...',
                hintStyle: TextStyle(color: Color(0xFFB5ADA6)),
              ),
            ),
          ),
          if (_cari.text.isNotEmpty)
            IconButton(
              tooltip: 'Hapus pencarian',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(_cari.clear),
              icon: const Icon(
                Icons.close_rounded,
                size: 21,
                color: WarnaTeras.teksSamar,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sinkronTerakhir() {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: SyncService.instance.terakhirBerhasil,
      builder: (context, waktu, _) => Row(
        children: [
          const Icon(
            Icons.update_rounded,
            size: 15,
            color: WarnaTeras.teksPudar,
          ),
          const SizedBox(width: 5),
          Text(
            labelSinkronTerakhir(waktu, DateTime.now()),
            style: const TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
          ),
        ],
      ),
    );
  }

  Widget _kisiKategori(bool adaTanpa, String? pilihan) {
    final tile = <Widget>[
      for (final c in kategoriDiKasir(_kategori))
        _tileKategori(
          c.name,
          categoryIconFromCodepoint(c.iconCodepoint),
          pilihan == c.id,
          () => _pilih(c.id),
        ),
      if (adaTanpa || pilihan == pilihanTanpaKategori)
        _tileKategori(
          namaTanpaKategori,
          kIkonTanpaKategori,
          pilihan == pilihanTanpaKategori,
          () => _pilih(pilihanTanpaKategori),
        ),
    ];
    if (tile.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, ukuran) {
        final lebar = (ukuran.maxWidth - 3 * 8) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tile) SizedBox(width: lebar, child: t)],
        );
      },
    );
  }

  Widget _tileKategori(
    String nama,
    IconData ikon,
    bool dipilih,
    VoidCallback onTap,
  ) {
    return Material(
      color: dipilih ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          width: 1.5,
          color: dipilih ? WarnaTeras.oranye : WarnaTeras.kartu,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ikon, size: 25, color: WarnaTeras.oranye),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: dipilih ? FontWeight.w600 : FontWeight.w400,
                    color: dipilih ? WarnaTeras.oranye : WarnaTeras.teks,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barisFilter(String pilihan, int jumlah) {
    final nama = pilihan == pilihanTanpaKategori
        ? namaTanpaKategori
        : _kategori.firstWhere((c) => c.id == pilihan).name;
    return Padding(
      padding: const EdgeInsets.only(top: 18, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$nama · $jumlah produk',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: WarnaTeras.teksPudar),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _pilihan = null),
            child: const Text(
              'Hapus filter',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kisiProduk(List<Product> produk) {
    final jumlahDiKeranjang = <String, int>{};
    for (final b in _keranjang.baris) {
      jumlahDiKeranjang[b.productId] =
          (jumlahDiKeranjang[b.productId] ?? 0) + b.qty;
    }
    return LayoutBuilder(
      builder: (context, ukuran) {
        final lebar = (ukuran.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in produk)
              SizedBox(
                width: lebar,
                child: _kartuProduk(p, jumlahDiKeranjang[p.id] ?? 0),
              ),
          ],
        );
      },
    );
  }

  Widget _kartuProduk(Product p, int diKeranjang) {
    return Material(
      color: WarnaTeras.kartu,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _tambah(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                FotoProduk(
                  path: p.imagePath,
                  ukuran: 140,
                  lebar: double.infinity,
                  sudut: 0,
                ),
                if (diKeranjang > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 26),
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: WarnaTeras.oranye,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        '$diKeranjang',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WarnaTeras.teks,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatRp(p.price),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const CircleAvatar(
                    radius: 13,
                    backgroundColor: WarnaTeras.oranyeLembut,
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
