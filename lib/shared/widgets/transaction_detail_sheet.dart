import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/db.dart';
import '../../features/sales/repositories/sales_repository.dart';
import '../../data/app_database.dart';
import '../../data/business_context.dart';
import 'business_logo.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/dashed_divider.dart';

class TransactionDetailSheet extends StatefulWidget {
  final Transaction transaction;

  const TransactionDetailSheet({super.key, required this.transaction});

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  final _salesRepo = SalesRepository(db);
  List<TransactionItem>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _salesRepo.getTransactionItems(widget.transaction.id);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final tx = widget.transaction;
    final isCash = tx.paymentMethod == 'cash';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detail Transaksi',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        // Nomor nota, bukan tx.id — id sekarang UUID internal.
                        tx.invoiceNo,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(color: Colors.grey.shade200, height: 1),

          // Receipt Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    // Store header — aplikasi difokuskan ke satu bisnis.
                    const BusinessLogo(size: 64),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.storeName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 1,
                      ),
                    ),
                    if ((BusinessContext.instance.activeBusiness?.address ??
                            '')
                        .trim()
                        .isNotEmpty)
                      Text(
                        BusinessContext.instance.activeBusiness!.address!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    const SizedBox(height: 16),
                    const DashedDivider(),
                    const SizedBox(height: 12),

                    // Transaction Info
                    _infoRow('Tanggal',
                        DateFormat('dd/MM/yyyy HH:mm').format(tx.createdAt)),
                    const SizedBox(height: 6),
                    _infoRow('No. Transaksi', tx.invoiceNo),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tipe Pesanan',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600)),
                        _orderTypeChip(tx.orderType, primaryColor),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const DashedDivider(),
                    const SizedBox(height: 12),

                    // Items
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: primaryColor),
                      )
                    else if (_items != null && _items!.isNotEmpty)
                      Column(
                        children: [
                          for (final item in _items!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
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
                                  ),
                                  if (item.notes != null &&
                                      item.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 12,
                                          color: Colors.deepOrange,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.notes!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.deepOrange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${item.qty} x Rp ${formatRupiah(item.priceAtSale)}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600),
                                      ),
                                      Text(
                                        'Rp ${formatRupiah(item.subtotal)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A1A1A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    else
                      Text('Tidak ada item',
                          style: TextStyle(color: Colors.grey.shade500)),

                    const SizedBox(height: 8),
                    const DashedDivider(),
                    const SizedBox(height: 12),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            'Rp ${formatRupiah(tx.total)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (isCash && tx.cashReceived != null) ...[
                      const SizedBox(height: 12),
                      _infoRow('Bayar (Cash)',
                          'Rp ${formatRupiah(tx.cashReceived!)}'),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Kembalian',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600)),
                          Text(
                            'Rp ${formatRupiah(tx.change ?? 0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Metode Pembayaran',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'QRIS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    const DashedDivider(),
                    const SizedBox(height: 16),

                    // Footer
                    const Text(
                      'Terima Kasih!',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Selamat menikmati',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(width: 12),
        // Expanded + rata kanan: nilai panjang (mis. ID transaksi berformat
        // UUID) turun baris alih-alih overflow.
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A1A)),
          ),
        ),
      ],
    );
  }

  Widget _orderTypeChip(String orderType, Color primaryColor) {
    final (label, icon) = switch (orderType) {
      'take_away' => ('Take Away', Icons.shopping_bag_rounded),
      'delivery' => ('Delivery', Icons.delivery_dining_rounded),
      _ => ('Dine In', Icons.restaurant_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: primaryColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
