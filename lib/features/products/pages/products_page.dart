import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../repositories/product_repository.dart';
import '../../../data/app_database.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/services/image_storage_service.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/constants/category_icons.dart';
import '../../../shared/ui/deretan_kategori.dart';
import '../../../shared/ui/kotak_cari.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_tambah.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../widgets/baris_produk.dart';
import '../sheets/product_form_sheet.dart';

/// Daftar Produk (desain): cari · deretan kategori · baris produk ·
/// tombol tambah. Ketuk baris untuk mengedit.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _productRepo = ProductRepository(db);
  String _searchQuery = '';
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    // S12: Defense-in-depth — block direct navigation tanpa permission.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        SessionManager.instance.requirePermission('manage_products');
      } on StateError {
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  Future<void> _openForm(BuildContext ctx, {Product? editing}) async {
    final screenHeight = MediaQuery.of(ctx).size.height;
    final result = await showModalBottomSheet<FormResult>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Tap di luar form diperlakukan sama seperti tombol back: barrier
      // memanggil Navigator.maybePop() yang selalu lewat PopScope milik
      // ProductFormSheet, jadi dialog "Buang perubahan?" tetap muncul
      // kalau form sudah diisi.
      isDismissible: true,
      // Tetap false: geser-turun memanggil Navigator.pop() langsung tanpa
      // melewati PopScope, sehingga input user bisa hilang tanpa konfirmasi.
      enableDrag: false,
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
      builder: (_) => ProductFormSheet(editing: editing),
    );

    if (result == null) return;
    if (!mounted) return;

    try {
      // Primary key WAJIB UUID: ID berbasis jam bisa bentrok antar-device
      // saat sync (dua HP membuat produk pada milidetik yang sama).
      final productId = editing?.id ?? newUuid();

      await _productRepo.upsertProduct(
        id: productId,
        name: result.name,
        price: result.price,
        categoryId: result.categoryId,
        hasSpicyOption: result.hasSpicyOption,
        hasSweetOption: result.hasSweetOption,
        hasIceOption: result.hasIceOption,
        imagePath: result.imagePath,
      );

      // Gambar lama dibuang HANYA setelah penyimpanan sungguh berhasil.
      // Kalau dihapus lebih awal (mis. saat memilih foto baru di form) lalu
      // penyimpanan gagal, produk kehilangan gambarnya tanpa sebab.
      final gambarLama = editing?.imagePath;
      if (gambarLama != null &&
          gambarLama.isNotEmpty &&
          gambarLama != result.imagePath) {
        await ImageStorageService().hapus(gambarLama);
      }

      if (!mounted) return;
      AppToast.success(context,
          editing == null ? '${result.name} ditambahkan' : 'Perubahan disimpan');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal: $e');
    }
  }

  Future<void> _hapus(Product p) async {
    final yakin = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.delete_outline_rounded,
      judul: 'Hapus produk?',
      catatan: '${p.name} akan dihapus dari daftar produk dan halaman kasir.',
      labelAksi: 'Hapus',
    );
    if (!yakin) return;

    try {
      await _productRepo.deleteProduct(p.id);
      if (!mounted) return;
      AppToast.success(context, '${p.name} dihapus');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal menghapus: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tanpa tarik-untuk-refresh: refresh lewat tombol di header, dan daftar
    // ini mendengarkan database sehingga ikut berubah sendiri.
    return StreamBuilder<List<Category>>(
      stream: _productRepo.watchCategories(),
      builder: (context, catSnap) {
        final kategori = catSnap.data ?? const <Category>[];
        final byId = {for (final c in kategori) c.id: c};
        return Stack(
          children: [
            StreamBuilder<List<Product>>(
              stream: _productRepo.watchProducts(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorStateWidget(
                    title: 'Gagal memuat produk',
                    onRetry: () => setState(() {}),
                  );
                }
                final semua = snap.data;
                final tampil = semua == null ? null : _saring(semua);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    KotakCari(
                      petunjuk: 'Cari produk...',
                      onBerubah: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Kategori',
                      style: TextStyle(
                        fontSize: TeksTeras.judul,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DeretanKategori(
                      terpilih: _selectedCategoryId,
                      onPilih: (id) => setState(() => _selectedCategoryId = id),
                      isi: [
                        const ChipKategori(
                          id: null,
                          label: 'Semua',
                          ikon: Icons.apps_rounded,
                        ),
                        for (final c in kategori)
                          ChipKategori(
                            id: c.id,
                            label: c.name,
                            ikon: categoryIconFromCodepoint(c.iconCodepoint),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (tampil == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (tampil.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Produk tidak ditemukan',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: TeksTeras.biasa,
                            color: WarnaTeras.teksPudar,
                          ),
                        ),
                      )
                    else
                      for (final p in tampil) ...[
                        BarisProduk(
                          produk: p,
                          namaKategori: byId[p.categoryId]?.name ?? 'Tanpa Kategori',
                          ikonKategori: byId[p.categoryId] == null
                              ? Icons.block_rounded
                              : categoryIconFromCodepoint(
                                  byId[p.categoryId]!.iconCodepoint),
                          onEdit: () => _openForm(context, editing: p),
                          onHapus: () => _hapus(p),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: TombolTambah(
                tooltip: 'Tambah produk',
                onTap: () => _openForm(context),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Saring menurut kategori terpilih dan kata cari.
  List<Product> _saring(List<Product> semua) {
    final cari = _searchQuery.trim().toLowerCase();
    return [
      for (final p in semua)
        if ((_selectedCategoryId == null || p.categoryId == _selectedCategoryId) &&
            (cari.isEmpty || p.name.toLowerCase().contains(cari)))
          p,
    ];
  }
}
