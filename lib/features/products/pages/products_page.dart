import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../widgets/product_search_bar.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/product_tile.dart';
import '../sheets/product_form_sheet.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _searchQuery = '';
  String? _selectedCategoryId;

  Future<void> _openForm(BuildContext context, {Product? editing}) async {
    final result = await showModalBottomSheet<FormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(editing: editing),
    );

    if (result == null) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      final productId =
          editing?.id ?? 'prod_${DateTime.now().millisecondsSinceEpoch}';

      await db.upsertProduct(
        id: productId,
        name: result.name,
        price: result.price,
        barcode: result.barcode,
        categoryId: result.categoryId,
        trackStock: result.trackStock,
        stock: result.stock,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            editing == null
                ? 'Produk berhasil ditambahkan'
                : 'Produk berhasil diperbarui',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, Product p) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Hapus Produk?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                'Produk "${p.name}" akan dihapus permanen dan tidak dapat dikembalikan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Hapus',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await db.deleteProduct(p.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Produk berhasil dihapus'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal menghapus: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
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
            stream: db.watchCategories(),
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
              stream: db.watchCategories(),
              builder: (context, catSnapshot) {
                final categories = catSnapshot.data ?? [];
                final categoryMap = {for (var c in categories) c.id: c.name};

                return StreamBuilder<List<Product>>(
                  stream: db.watchProducts(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: primaryColor,
                          strokeWidth: 2,
                        ),
                      );
                    }

                    var items = snapshot.data!;

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

                    return ListView.builder(
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty || _selectedCategoryId != null
                ? 'Tidak ada produk'
                : 'Belum ada produk',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedCategoryId != null
                ? 'Coba ubah filter pencarian'
                : 'Tap tombol + untuk menambah produk',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
