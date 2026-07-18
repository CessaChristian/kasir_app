import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/app_toast.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../../data/models/sale_line.dart';
import '../../shared/auth/session_manager.dart';
import 'dart:io';
import 'models/cart_item.dart';
import 'cart_page.dart';
import '../../shared/widgets/error_state_widget.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _CartLine {
  final Product product;
  int qty;
  String? notes;

  _CartLine({required this.product, required this.qty, this.notes});

  int get subtotal => product.price * qty;
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  final List<_CartLine> _cart = [];
  final Set<String> _addingProducts = {};
  // C4: Cache hasil File.existsSync agar tidak blocking main thread setiap rebuild
  final Map<String, bool> _imageExistsCache = {};
  String? _selectedCategoryId;
  String _searchQuery = '';
  final GlobalKey _cartIconKey = GlobalKey();

  bool _imageExists(String? path) {
    if (path == null || path.isEmpty) return false;
    return _imageExistsCache.putIfAbsent(path, () => File(path).existsSync());
  }

  int get _total => _cart.fold(0, (s, l) => s + l.subtotal);

  Future<void> _playAddToCartAnimation(Offset startPosition) async {
    HapticFeedback.lightImpact();

    final cartIconContext = _cartIconKey.currentContext;
    if (cartIconContext == null) return;

    final cartIconBox = cartIconContext.findRenderObject() as RenderBox;
    final cartIconPosition = cartIconBox.localToGlobal(Offset.zero);
    final cartIconCenter = Offset(
      cartIconPosition.dx + cartIconBox.size.width / 2,
      cartIconPosition.dy + cartIconBox.size.height / 2,
    );

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    final positionAnimation =
        Tween<Offset>(begin: startPosition, end: cartIconCenter).animate(
          CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
        );

    final scaleAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
    );

    final opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: animationController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    final primaryColor = Theme.of(context).colorScheme.primary;

    overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          return Positioned(
            left: positionAnimation.value.dx - 16,
            top: positionAnimation.value.dy - 16,
            child: Transform.scale(
              scale: scaleAnimation.value,
              child: Opacity(
                opacity: opacityAnimation.value,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    overlay.insert(overlayEntry);
    await animationController.forward();
    overlayEntry.remove();
    animationController.dispose();
  }

  /// Tampilkan pilihan level pedas, return pilihan atau null jika dibatalkan
  Future<String?> _showSpicySheet(Product p) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pilih tingkat kepedasan:',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              for (final option in [
                ('Tidak Pedas', 1, const Color(0xFF94A3B8)),
                ('Sedang', 2, const Color(0xFFF59E0B)),
                ('Pedas', 3, const Color(0xFFDC2626)),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, option.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            // Heat level dots indicator (3 dots)
                            Row(
                              children: List.generate(
                                3,
                                (i) => Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: i < option.$2
                                        ? option.$3
                                        : Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              option.$1,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade500,
                  ),
                  child: const Text('Lewati'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToCart(Product p, Offset tapPosition) async {
    // Lock per-produk: cegah tap ganda sebelum setState selesai
    if (_addingProducts.contains(p.id)) return;
    _addingProducts.add(p.id);

    try {
      if (p.trackStock && (p.stock ?? 0) <= 0) {
        if (!mounted) return;
        AppToast.error(context, 'Stok "${p.name}" sudah habis');
        return;
      }

      final idx = _cart.indexWhere((x) => x.product.id == p.id);

      if (idx != -1) {
        if (p.trackStock && _cart[idx].qty >= (p.stock ?? 0)) {
          if (!mounted) return;
          AppToast.warning(
              context, 'Stok "${p.name}" hanya ${p.stock}, tidak bisa ditambah lagi');
          return;
        }
        await _playAddToCartAnimation(tapPosition);
        if (!mounted) return;
        setState(() => _cart[idx].qty += 1);
        return;
      }

      // Produk baru → tanya level pedas jika ada
      String? notes;
      if (p.hasSpicyOption) {
        notes = await _showSpicySheet(p);
      }

      if (!mounted) return;
      await _playAddToCartAnimation(tapPosition);
      if (!mounted) return;
      setState(() {
        _cart.add(_CartLine(product: p, qty: 1, notes: notes));
      });
    } finally {
      _addingProducts.remove(p.id);
    }
  }

  void _incQty(int index) {
    if (index >= _cart.length) return;
    final item = _cart[index];
    if (item.product.trackStock) {
      final maxStock = item.product.stock ?? 0;
      if (item.qty >= maxStock) return;
    }
    _cart[index].qty += 1;
  }

  void _decQty(int index) {
    setState(() {
      final q = _cart[index].qty - 1;
      if (q <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].qty = q;
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _clearCart() => setState(() => _cart.clear());

  List<SaleLine> _cartToSaleLines() {
    return _cart.map((l) {
      return SaleLine(
        productId: l.product.id,
        productName: l.product.name,
        qty: l.qty,
        priceAtSale: l.product.price,
        trackStock: l.product.trackStock,
        notes: l.notes,
      );
    }).toList();
  }

  String _generateTxId() {
    final now = DateTime.now();
    final dd = DateFormat('dd').format(now);
    final mm = DateFormat('MM').format(now);
    final yy = DateFormat('yy').format(now);
    // Gunakan microsecond agar unik meski checkout bersamaan
    final micro = (now.microsecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    return 'TRX/$dd/$mm/$yy/$micro';
  }

  Future<void> _checkout(
    PaymentMethod paymentMethod,
    int? cashReceived,
    String orderType,
  ) async {
    final isCash = paymentMethod == PaymentMethod.cash;

    try {
      final session = SessionManager.instance.currentSession;

      await db.createSale(
        transactionId: _generateTxId(),
        lines: _cartToSaleLines(),
        paymentMethod: isCash ? 'cash' : 'qris',
        orderType: orderType,
        cashReceived: cashReceived,
        cashierUserId: session?.userId,
        shiftId: session?.shiftId,
      );

      _clearCart();
    } catch (e) {
      rethrow;
    }
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CartPage(
        cartItems: _cart.map((item) {
          return CartItem(
            productId: item.product.id,
            productName: item.product.name,
            pricePerUnit: item.product.price,
            qty: item.qty,
            maxStock: item.product.trackStock ? item.product.stock : null,
            trackStock: item.product.trackStock,
            notes: item.notes,
          );
        }).toList(),
        onClearCart: () => setState(_clearCart),
        onIncrement: (index) => setState(() => _incQty(index)),
        onDecrement: (index) => setState(() => _decQty(index)),
        onRemoveItem: (index) => setState(() => _removeItem(index)),
        onCheckout: _checkout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
                decoration: InputDecoration(
                  hintText: 'Cari produk...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),

          // Category Filter
          SizedBox(
            height: 48,
            child: StreamBuilder<List<Category>>(
              stream: db.watchCategories(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SizedBox.shrink();
                final categories = snapshot.data ?? [];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildCategoryChip(
                      label: 'Semua',
                      isSelected: _selectedCategoryId == null,
                      onTap: () => setState(() => _selectedCategoryId = null),
                    ),
                    const SizedBox(width: 8),
                    for (final c in categories) ...[
                      _buildCategoryChip(
                        label: c.name,
                        isSelected: _selectedCategoryId == c.id,
                        onTap: () => setState(() => _selectedCategoryId = c.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Product Grid
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: db.watchProducts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorStateWidget(
                    title: 'Gagal memuat produk',
                    onRetry: () => setState(() {}),
                  );
                }
                var items = snapshot.data ?? [];

                if (_selectedCategoryId != null) {
                  items = items
                      .where((p) => p.categoryId == _selectedCategoryId)
                      .toList();
                }

                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  items = items
                      .where((p) => p.name.toLowerCase().contains(query))
                      .toList();
                }

                if (items.isEmpty) return _buildEmptyState();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    const cols = 3;
                    const spacing = 10.0;
                    const hPad = 32.0;
                    final cardWidth =
                        (constraints.maxWidth - hPad - (cols - 1) * spacing) /
                        cols;

                    // Kelompokkan produk menjadi baris-baris @3
                    final rows = <List<Product>>[];
                    for (int i = 0; i < items.length; i += cols) {
                      rows.add(
                        items.sublist(i, (i + cols).clamp(0, items.length)),
                      );
                    }

                    // C4: Pre-compute pakai cache — existsSync hanya dipanggil
                    // sekali per file selama lifecycle widget, tidak per rebuild.
                    final rowHasImageList = rows
                        .map((rowItems) =>
                            rowItems.any((p) => _imageExists(p.imagePath)))
                        .toList();

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: rows.length,
                      itemBuilder: (_, rowIdx) {
                        final rowItems = rows[rowIdx];
                        final rowHasImage = rowHasImageList[rowIdx];
                        final noImageHeight = cardWidth / 1.12;

                        final rowWidget = Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < cols; i++) ...[
                              if (i > 0) const SizedBox(width: spacing),
                              Expanded(
                                child: i < rowItems.length
                                    ? _buildProductCard(
                                        rowItems[i],
                                        rowHasImage: rowHasImage,
                                        cardWidth: cardWidth,
                                      )
                                    : const SizedBox(),
                              ),
                            ],
                          ],
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          // Baris bergambar: tinggi mengikuti konten (IntrinsicHeight)
                          // Baris tanpa gambar: tinggi tetap & kompak
                          child: rowHasImage
                              ? IntrinsicHeight(child: rowWidget)
                              : SizedBox(height: noImageHeight, child: rowWidget),
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
      bottomNavigationBar: _buildCartBar(),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(
    Product p, {
    required bool rowHasImage,
    required double cardWidth,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final hasLowStock = p.trackStock && (p.stock ?? 0) <= 5;
    final hasImage =
        p.imagePath != null &&
        p.imagePath!.isNotEmpty &&
        File(p.imagePath!).existsSync();
    final imgHeight = cardWidth * 0.60;

    Widget content;

    if (hasImage) {
      // === Kartu DENGAN gambar ===
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(p.imagePath!),
              height: imgHeight,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Rp ${formatRupiah(p.price)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p.hasSpicyOption) ...[
                const SizedBox(width: 3),
                const Icon(Icons.local_fire_department_rounded,
                    size: 13, color: Colors.deepOrange),
              ],
            ],
          ),
          if (p.trackStock) ...[
            const SizedBox(height: 3),
            _stockBadge(hasLowStock, p.stock),
          ],
        ],
      );
    } else {
      // === Kartu TANPA gambar — nama di tengah, harga di bawah ===
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Text(
                p.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Rp ${formatRupiah(p.price)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p.hasSpicyOption) ...[
                const SizedBox(width: 3),
                const Icon(Icons.local_fire_department_rounded,
                    size: 13, color: Colors.deepOrange),
              ],
            ],
          ),
          if (p.trackStock) ...[
            const SizedBox(height: 3),
            _stockBadge(hasLowStock, p.stock),
          ],
        ],
      );
    }

    return GestureDetector(
      onTapDown: (details) => _addToCart(p, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasLowStock ? Colors.red.shade200 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: content,
        ),
      ),
    );
  }

  Widget _stockBadge(bool hasLowStock, int? stock) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: hasLowStock ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Stok: ${stock ?? 0}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: hasLowStock ? Colors.red : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 32,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'Produk tidak ditemukan'
                : (_selectedCategoryId != null
                      ? 'Tidak ada produk di kategori ini'
                      : 'Belum ada produk'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: _openCart,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  key: _cartIconKey,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(
                          Icons.shopping_cart_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      if (_cart.isNotEmpty)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${_cart.length}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total Belanja',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rp ${formatRupiah(_total)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
