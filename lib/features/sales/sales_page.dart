import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../../data/models/sale_line.dart';
import '../../shared/auth/session_manager.dart';
import 'models/cart_item.dart';
import 'cart_page.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _CartLine {
  final Product product;
  int qty;

  _CartLine({required this.product, required this.qty});

  int get subtotal => product.price * qty;
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  final List<_CartLine> _cart = [];
  String? _selectedCategoryId;
  String _searchQuery = '';
  final GlobalKey _cartIconKey = GlobalKey();

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

    final positionAnimation = Tween<Offset>(
      begin: startPosition,
      end: cartIconCenter,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: Curves.easeInOut,
    ));

    final scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.3,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: Curves.easeInOut,
    ));

    final opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: animationController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    ));

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

  Future<void> _addToCart(Product p, Offset tapPosition) async {
    await _playAddToCartAnimation(tapPosition);
    
    setState(() {
      final idx = _cart.indexWhere((x) => x.product.id == p.id);
      if (idx == -1) {
        _cart.add(_CartLine(product: p, qty: 1));
      } else {
        _cart[idx].qty += 1;
      }
    });
  }

  void _incQty(int index) {
    setState(() => _cart[index].qty += 1);
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
      );
    }).toList();
  }

  String _generateTxId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> _checkout(PaymentMethod paymentMethod, int? cashReceived) async {
    final isCash = paymentMethod == PaymentMethod.cash;

    try {
      final session = SessionManager.instance.currentSession;
      
      await db.createSale(
        transactionId: _generateTxId(),
        lines: _cartToSaleLines(),
        paymentMethod: isCash ? 'cash' : 'qris',
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
          );
        }).toList(),
        onClearCart: () {
          setState(() => _clearCart());
        },
        onIncrement: (index) {
          setState(() => _incQty(index));
        },
        onDecrement: (index) {
          setState(() => _decQty(index));
        },
        onRemoveItem: (index) {
          setState(() => _removeItem(index));
        },
        onCheckout: _checkout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
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
                    color: Colors.black.withValues(alpha:0.04),
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
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  prefixIcon: Icon(Icons.search_rounded, color: primaryColor, size: 22),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 20),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                var items = snapshot.data ?? [];
                
                if (_selectedCategoryId != null) {
                  items = items.where((p) => p.categoryId == _selectedCategoryId).toList();
                }

                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  items = items.where((p) => p.name.toLowerCase().contains(query)).toList();
                }

                if (items.isEmpty) {
                  return _buildEmptyState();
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final p = items[index];
                    return _buildProductCard(p);
                  },
                );
              },
            ),
          ),
        ],
      ),
      
      // Bottom Cart Bar
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
                    color: primaryColor.withValues(alpha:0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.04),
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
  
  Widget _buildProductCard(Product p) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final hasLowStock = p.trackStock && (p.stock ?? 0) <= 5;
    
    return GestureDetector(
      onTapDown: (details) {
        _addToCart(p, details.globalPosition);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasLowStock ? Colors.red.shade200 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product name
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              // Price
              Text(
                'Rp ${formatRupiah(p.price)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              // Stock info
              if (p.trackStock) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasLowStock ? Colors.red.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Stok: ${p.stock ?? 0}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hasLowStock ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
            color: Colors.black.withValues(alpha:0.08),
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
                // Cart icon with badge
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
                // Total info
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
                // Arrow
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
