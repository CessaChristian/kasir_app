import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../repositories/product_repository.dart';
import '../../../data/app_database.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/sync_refresh.dart';
import '../../../shared/services/image_storage_service.dart';
import '../../../shared/auth/session_manager.dart';
import '../widgets/product_search_bar.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/product_tile.dart';
import '../sheets/product_form_sheet.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../../../shared/widgets/empty_state_widget.dart';

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
        barcode: result.barcode,
        categoryId: result.categoryId,
        hasSpicyOption: result.hasSpicyOption,
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
          editing == null ? 'Produk berhasil ditambahkan' : 'Produk berhasil diperbarui');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal: $e');
    }
  }

  Future<void> _delete(BuildContext ctx, Product p) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => ConfirmDeleteDialog(
        title: 'Hapus Produk?',
        message: 'Produk "${p.name}" akan dihapus permanen dan tidak dapat dikembalikan.',
      ),
    );

    if (confirmed != true) return;

    try {
      await _productRepo.deleteProduct(p.id);
      if (!mounted) return;
      AppToast.success(context, 'Produk berhasil dihapus');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal menghapus: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        backgroundColor: primaryColor,
        elevation: 2,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: Column(
        children: [
          // Search Bar
          ProductSearchBar(
            query: _searchQuery,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          // Category Filter
          StreamBuilder<List<Category>>(
            stream: _productRepo.watchCategories(),
            builder: (context, snapshot) {
              final categories = snapshot.data ?? [];
              return CategoryFilterBar(
                selectedCategoryId: _selectedCategoryId,
                categories: categories,
                onCategorySelected: (id) =>
                    setState(() => _selectedCategoryId = id),
              );
            },
          ),
          // Product List - Using single combined stream for better performance
          Expanded(
            child: StreamBuilder<List<Category>>(
              stream: _productRepo.watchCategories(),
              builder: (context, catSnapshot) {
                final categories = catSnapshot.data ?? [];
                final categoryMap = {for (var c in categories) c.id: c.name};

                return StreamBuilder<List<Product>>(
                  stream: _productRepo.watchProducts(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorStateWidget(
                        title: 'Gagal memuat produk',
                        onRetry: () => setState(() {}),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: primaryColor,
                          strokeWidth: 2,
                        ),
                      );
                    }

                    var items = snapshot.data ?? [];

                    // Filter by category
                    if (_selectedCategoryId != null) {
                      items = items
                          .where(
                            (p) =>
                                p.categoryId == _selectedCategoryId.toString(),
                          )
                          .toList();
                    }

                    // Filter by search
                    if (_searchQuery.isNotEmpty) {
                      final query = _searchQuery.toLowerCase();
                      items = items
                          .where((p) => p.name.toLowerCase().contains(query))
                          .toList();
                    }

                    if (items.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return SyncRefresh(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final p = items[i];
                          final categoryName = p.categoryId != null
                              ? categoryMap[p.categoryId] ?? 'Tanpa Kategori'
                              : 'Tanpa Kategori';

                          return ProductTile(
                            product: p,
                            categoryName: categoryName,
                            onTap: () => _openForm(context, editing: p),
                            onEdit: () => _openForm(context, editing: p),
                            onDelete: () => _delete(context, p),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasFilter = _searchQuery.isNotEmpty || _selectedCategoryId != null;
    return EmptyStateWidget(
      icon: Icons.inventory_2_outlined,
      title: hasFilter ? 'Tidak ada produk' : 'Belum ada produk',
      subtitle: hasFilter
          ? 'Coba ubah filter pencarian'
          : 'Tap tombol + untuk menambah produk',
    );
  }
}
