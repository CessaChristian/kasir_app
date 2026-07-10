import 'package:flutter/material.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/widgets/app_toast.dart';
import 'models/cart_item.dart';
import 'sheets/cash_payment_sheet.dart';
import 'widgets/payment_success_dialog.dart';

enum PaymentMethod { cash, qris }

enum OrderType { dineIn, takeAway, delivery }

extension OrderTypeExt on OrderType {
  String get value {
    switch (this) {
      case OrderType.dineIn:
        return 'dine_in';
      case OrderType.takeAway:
        return 'take_away';
      case OrderType.delivery:
        return 'delivery';
    }
  }

  String get label {
    switch (this) {
      case OrderType.dineIn:
        return 'Dine In';
      case OrderType.takeAway:
        return 'Take Away';
      case OrderType.delivery:
        return 'Delivery';
    }
  }

  IconData get icon {
    switch (this) {
      case OrderType.dineIn:
        return Icons.restaurant_rounded;
      case OrderType.takeAway:
        return Icons.shopping_bag_rounded;
      case OrderType.delivery:
        return Icons.delivery_dining_rounded;
    }
  }
}

class CartPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final VoidCallback onClearCart;
  final Function(int index) onIncrement;
  final Function(int index) onDecrement;
  final Function(int index) onRemoveItem;
  final Future<void> Function(
      PaymentMethod paymentMethod, int? cashReceived, String orderType) onCheckout;

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
  OrderType _orderType = OrderType.dineIn;
  late List<CartItem> _localCartItems;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _localCartItems = List.from(widget.cartItems);
  }

  int get _total => _localCartItems.fold(0, (s, item) => s + item.subtotal);

  void _handleClearCart() {
    setState(() => _localCartItems.clear());
    widget.onClearCart();
  }

  void _handleIncrement(int index) {
    if (index >= _localCartItems.length) return;
    final item = _localCartItems[index];
    // Tombol + di-disable secara visual jika sudah max — guard ini hanya backup
    if (item.trackStock && item.maxStock != null && item.qty >= item.maxStock!) {
      return;
    }
    setState(() {
      _localCartItems[index] = item.copyWith(qty: item.qty + 1);
    });
    widget.onIncrement(index);
  }

  void _handleDecrement(int index) {
    setState(() {
      if (index < _localCartItems.length) {
        if (_localCartItems[index].qty <= 1) {
          _localCartItems.removeAt(index);
        } else {
          _localCartItems[index] = _localCartItems[index]
              .copyWith(qty: _localCartItems[index].qty - 1);
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
    if (_isProcessing) return;
    if (_localCartItems.isEmpty) {
      if (!mounted) return;
      AppToast.warning(context, 'Keranjang masih kosong');
      return;
    }

    // I5: Capture total SEKALI di awal checkout sebagai source of truth.
    // Ini memastikan toast kembalian, modal pembayaran, dan total yang
    // disimpan ke DB semuanya menggunakan angka yang sama.
    final checkoutTotal = _total;
    final isCash = _paymentMethod == PaymentMethod.cash;
    int? cashReceived;

    if (isCash) {
      cashReceived = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CashPaymentSheet(total: checkoutTotal),
      );
      if (cashReceived == null) return;
    } else {
      final confirm = await _showQRISConfirmDialog();
      if (confirm != true) return;
    }

    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onCheckout(_paymentMethod, cashReceived, _orderType.value);

      if (!mounted) return;

      // Layar sukses dengan kembalian BESAR — kasir harus tap "Selesai"
      // setelah menyerahkan kembalian (tidak bisa dismiss tap di luar).
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PaymentSuccessDialog(
          total: checkoutTotal,
          cashReceived: isCash ? cashReceived : null,
          orderType: _orderType.value,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _showQRISConfirmDialog() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.qr_code_rounded,
                    color: primaryColor, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Konfirmasi QRIS',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Total: Rp ${formatRupiah(_total)}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Pastikan pembayaran QRIS sudah diterima.',
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
                      child: const Text('Batal',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Sudah Dibayar',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kosongkan Keranjang?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Semua item akan dihapus dari keranjang.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
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
                      child: const Text('Batal',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Kosongkan',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) _handleClearCart();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _localCartItems.isEmpty;

    // M-C: Cegah swipe-down / back button menutup CartPage saat transaksi
    // sedang diproses. Tanpa ini, user bisa secara tidak sengaja menutup
    // sheet di tengah `db.createSale`, dan error toast tidak akan tampil
    // jika transaksi gagal — user mengira aman padahal harus retry.
    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          AppToast.warning(context, 'Tunggu transaksi selesai diproses');
        }
      },
      child: Container(
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
                const Expanded(
                  child: Text(
                    'Keranjang',
                    style: TextStyle(
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
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
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
                      _buildPaymentSection(),
                    ],
                  ),
          ),
        ],
      ),
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
            child: Icon(Icons.shopping_cart_outlined,
                size: 40, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          const Text(
            'Keranjang Kosong',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan produk dari halaman kasir',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item, int index) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isAtMaxStock =
        item.trackStock && item.maxStock != null && item.qty >= item.maxStock!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Kiri: nama + catatan + harga satuan
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          size: 11, color: Colors.deepOrange),
                      const SizedBox(width: 3),
                      Text(
                        item.notes!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'Rp ${formatRupiah(item.pricePerUnit)} × ${item.qty}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    if (isAtMaxStock) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'maks',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Kanan: subtotal + kontrol qty + hapus
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Rp ${formatRupiah(item.subtotal)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _handleDecrement(index),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.remove_rounded,
                                size: 15, color: Colors.grey.shade700),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${item.qty}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        InkWell(
                          onTap: isAtMaxStock
                              ? null
                              : () => _handleIncrement(index),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.add_rounded,
                                size: 15,
                                color: isAtMaxStock
                                    ? Colors.grey.shade300
                                    : primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _handleRemoveItem(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 17, color: Colors.red.shade400),
                    ),
                  ),
                ],
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
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Tipe Pesanan (chip inline) ----
              Row(
                children: [
                  const Text(
                    'Tipe Pesanan',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: OrderType.values.map((type) {
                        final isSelected = _orderType == type;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                left: type != OrderType.dineIn ? 5 : 0),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _orderType = type),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 7, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primaryColor
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? primaryColor
                                        : Colors.grey.shade300,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(type.icon,
                                        size: 13,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade600),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        type.label,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.grey.shade600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ---- Metode Pembayaran ----
              Row(
                children: [
                  const Text(
                    'Pembayaran',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildPaymentMethodButton(
                            label: 'Cash',
                            icon: Icons.payments_outlined,
                            isSelected:
                                _paymentMethod == PaymentMethod.cash,
                            onTap: () => setState(
                                () => _paymentMethod = PaymentMethod.cash),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildPaymentMethodButton(
                            label: 'QRIS',
                            icon: Icons.qr_code_rounded,
                            isSelected:
                                _paymentMethod == PaymentMethod.qris,
                            onTap: () => setState(
                                () => _paymentMethod = PaymentMethod.qris),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ---- Total ----
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Total Belanja',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A1A)),
                    ),
                    const Spacer(),
                    Text(
                      'Rp ${formatRupiah(_total)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ---- Tombol Bayar ----
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (isEmpty || _isProcessing) ? null : _handleCheckout,
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
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.shopping_cart_checkout_rounded,
                                size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Bayar Rp ${formatRupiah(_total)}',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
