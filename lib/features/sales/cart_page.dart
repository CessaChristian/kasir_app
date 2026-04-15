import 'package:flutter/material.dart';
import '../../utils/currency_formatter.dart';
import 'models/cart_item.dart';
import 'sheets/cash_payment_sheet.dart';

enum PaymentMethod { cash, qris }

class CartPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final VoidCallback onClearCart;
  final Function(int index) onIncrement;
  final Function(int index) onDecrement;
  final Function(int index) onRemoveItem;
  final Future<void> Function(PaymentMethod paymentMethod, int? cashReceived) onCheckout;

  const CartPage({
    super.key,
    required this.cartItems,
    required this.onClearCart,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemoveItem,
    required this.onCheckout,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  late List<CartItem> _localCartItems;

  @override
  void initState() {
    super.initState();
    _localCartItems = List.from(widget.cartItems);
  }

  int get _total => _localCartItems.fold(0, (s, item) => s + item.subtotal);

  void _handleClearCart() {
    setState(() {
      _localCartItems.clear();
    });
    widget.onClearCart();
  }

  void _handleIncrement(int index) {
    setState(() {
      if (index < _localCartItems.length) {
        _localCartItems[index] = CartItem(
          productId: _localCartItems[index].productId,
          productName: _localCartItems[index].productName,
          pricePerUnit: _localCartItems[index].pricePerUnit,
          qty: _localCartItems[index].qty + 1,
        );
      }
    });
    widget.onIncrement(index);
  }

  void _handleDecrement(int index) {
    setState(() {
      if (index < _localCartItems.length) {
        if (_localCartItems[index].qty <= 1) {
          _localCartItems.removeAt(index);
        } else {
          _localCartItems[index] = CartItem(
            productId: _localCartItems[index].productId,
            productName: _localCartItems[index].productName,
            pricePerUnit: _localCartItems[index].pricePerUnit,
            qty: _localCartItems[index].qty - 1,
          );
        }
      }
    });
    widget.onDecrement(index);
  }

  void _handleRemoveItem(int index) {
    setState(() {
      if (index < _localCartItems.length) {
        _localCartItems.removeAt(index);
      }
    });
    widget.onRemoveItem(index);
  }

  Future<void> _handleCheckout() async {
    if (_localCartItems.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Keranjang masih kosong'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final isCash = _paymentMethod == PaymentMethod.cash;
    int? cashReceived;

    if (isCash) {
      cashReceived = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CashPaymentSheet(total: _total),
      );

      if (cashReceived == null) return;
    } else {
      final confirm = await _showQRISConfirmDialog();
      if (confirm != true) return;
    }

    try {
      await widget.onCheckout(_paymentMethod, cashReceived);
      
      if (!mounted) return;
      
      String message = 'Transaksi berhasil!';
      if (isCash && cashReceived != null) {
        final change = cashReceived - _total;
        if (change > 0) {
          message = 'Transaksi berhasil! Kembalian: Rp ${formatRupiah(change)}';
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  Future<bool?> _showQRISConfirmDialog() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return showDialog<bool>(
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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.qr_code_rounded, color: primaryColor, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Konfirmasi QRIS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: Rp ${formatRupiah(_total)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pastikan pembayaran QRIS sudah diterima.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
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
                      child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Sudah Dibayar', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _showClearCartDialog() async {
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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kosongkan Keranjang?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Semua item akan dihapus dari keranjang.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
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
                      child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Kosongkan', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    if (confirmed == true) {
      _handleClearCart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _localCartItems.isEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Keranjang',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                if (!isEmpty)
                  TextButton.icon(
                    onPressed: _showClearCartDialog,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Kosongkan'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
          ),
          
          Divider(color: Colors.grey.shade200, height: 1),
          
          // Body
          Expanded(
            child: isEmpty
                ? _buildEmptyCart()
                : Column(
                    children: [
                      // Cart items list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _localCartItems.length,
                          itemBuilder: (context, index) {
                            final item = _localCartItems[index];
                            return _buildCartItem(item, index);
                          },
                        ),
                      ),
                      
                      // Payment section
                      _buildPaymentSection(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyCart() {
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
              Icons.shopping_cart_outlined,
              size: 40,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Keranjang Kosong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan produk dari halaman kasir',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCartItem(CartItem item, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rp ${formatRupiah(item.pricePerUnit)} × ${item.qty}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Rp ${formatRupiah(item.subtotal)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Quantity controls
          Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _handleDecrement(index),
                      icon: const Icon(Icons.remove_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      color: Colors.grey.shade700,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${item.qty}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _handleIncrement(index),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      color: primaryColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              IconButton(
                onPressed: () => _handleRemoveItem(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: 'Hapus produk',
                style: IconButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPaymentSection() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isEmpty = _localCartItems.isEmpty;
    
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payment method
              const Text(
                'Metode Pembayaran',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodButton(
                      label: 'Cash',
                      icon: Icons.payments_outlined,
                      isSelected: _paymentMethod == PaymentMethod.cash,
                      onTap: () => setState(() => _paymentMethod = PaymentMethod.cash),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPaymentMethodButton(
                      label: 'QRIS',
                      icon: Icons.qr_code_rounded,
                      isSelected: _paymentMethod == PaymentMethod.qris,
                      onTap: () => setState(() => _paymentMethod = PaymentMethod.qris),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Total
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Total Belanja',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
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
              
              const SizedBox(height: 16),
              
              // Checkout button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isEmpty ? null : _handleCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_cart_checkout_rounded),
                      const SizedBox(width: 8),
                      Text(
                        'Bayar Rp ${formatRupiah(_total)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPaymentMethodButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
