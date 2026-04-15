import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../utils/currency_formatter.dart';

/// Tampilkan bottom sheet detail karyawan
void showEmployeeDetailSheet(BuildContext context, EmployeeReportSummary employee) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => EmployeeDetailSheet(employee: employee),
  );
}

class EmployeeDetailSheet extends StatelessWidget {
  final EmployeeReportSummary employee;

  const EmployeeDetailSheet({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final e = employee;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          e.username[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.username,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${e.totalTransactions} transaksi • ${e.shifts.length} shift',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              
              Divider(height: 1, color: Colors.grey.shade200),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards
                      Row(
                        children: [
                          Expanded(
                            child: _DetailSummaryCard(
                              icon: Icons.receipt_long_rounded,
                              iconColor: primaryColor,
                              label: 'Total Pesanan',
                              value: '${e.totalTransactions}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DetailSummaryCard(
                              icon: Icons.account_balance_wallet_rounded,
                              iconColor: Colors.green.shade700,
                              label: 'Total Pendapatan',
                              value: 'Rp ${formatRupiah(e.totalIncome)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // Payment Methods
                      _buildSectionTitle('Metode Pembayaran'),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _DetailPaymentRow(
                              icon: Icons.payments_rounded,
                              iconColor: Colors.green.shade700,
                              label: 'Cash',
                              count: e.cashOrders,
                              total: e.cashTotal,
                            ),
                            Divider(height: 1, color: Colors.grey.shade200),
                            _DetailPaymentRow(
                              icon: Icons.qr_code_rounded,
                              iconColor: primaryColor,
                              label: 'QRIS',
                              count: e.qrisOrders,
                              total: e.qrisTotal,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Top Products
                      if (e.topProducts.isNotEmpty) ...[
                        _buildSectionTitle('Produk Terlaris'),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: e.topProducts.asMap().entries.map((entry) {
                              final i = entry.key;
                              final p = entry.value;
                              return _DetailProductRow(
                                rank: i + 1,
                                name: p.productName,
                                qty: p.totalQty,
                                total: p.totalSales,
                                primaryColor: primaryColor,
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Shift History
                      _buildSectionTitle('Riwayat Shift'),
                      const SizedBox(height: 10),
                      ...e.shifts.map((shift) => _DetailShiftRow(shift: shift, primaryColor: primaryColor)),
                      const SizedBox(height: 24),
                      
                      // Transactions List
                      Row(
                        children: [
                          Expanded(child: _buildSectionTitle('Daftar Transaksi')),
                          Text(
                            '${e.transactions.length} transaksi',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...e.transactions.map((tx) => _DetailTransactionRow(transaction: tx, primaryColor: primaryColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
    );
  }
}

class _DetailSummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _DetailSummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DetailPaymentRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final int total;

  const _DetailPaymentRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('$count transaksi', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Text(
            'Rp ${formatRupiah(total)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DetailProductRow extends StatelessWidget {
  final int rank;
  final String name;
  final int qty;
  final int total;
  final Color primaryColor;

  const _DetailProductRow({
    required this.rank,
    required this.name,
    required this.qty,
    required this.total,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: rank == 1 ? primaryColor : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: rank == 1 ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          Text('$qty terjual', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(width: 8),
          Text('Rp ${formatRupiah(total)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DetailShiftRow extends StatelessWidget {
  final ShiftInfo shift;
  final Color primaryColor;

  const _DetailShiftRow({required this.shift, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final startTime = DateFormat('HH:mm').format(shift.startAt);
    final endTime = shift.endAt != null ? DateFormat('HH:mm').format(shift.endAt!) : 'Aktif';
    final isActive = shift.endAt == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? primaryColor.withValues(alpha:0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: isActive ? Border.all(color: primaryColor.withValues(alpha:0.3)) : null,
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, size: 18, color: isActive ? primaryColor : Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$startTime - $endTime', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('AKTIF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ],
                ),
                Text('${shift.transactionCount} transaksi', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Text(
            'Rp ${formatRupiah(shift.totalIncome)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryColor),
          ),
        ],
      ),
    );
  }
}

class _DetailTransactionRow extends StatefulWidget {
  final Transaction transaction;
  final Color primaryColor;

  const _DetailTransactionRow({required this.transaction, required this.primaryColor});

  @override
  State<_DetailTransactionRow> createState() => _DetailTransactionRowState();
}

class _DetailTransactionRowState extends State<_DetailTransactionRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  List<TransactionItem>? _items;
  bool _loading = false;

  Future<void> _loadItems() async {
    if (_items != null) return;
    setState(() => _loading = true);
    final items = await db.getTransactionItems(widget.transaction.id);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  void _toggle() {
    if (!_expanded) _loadItems();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final isCash = tx.paymentMethod == 'cash';
    final primary = widget.primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _expanded ? Colors.grey.shade100 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: _expanded
            ? Border.all(color: primary.withValues(alpha:0.2))
            : null,
      ),
      child: Column(
        children: [
          // Transaction header — tappable
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isCash ? Colors.green.shade50 : primary.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      isCash ? Icons.payments_rounded : Icons.qr_code_rounded,
                      color: isCash ? Colors.green.shade700 : primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rp ${formatRupiah(tx.total)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          DateFormat('HH:mm').format(tx.createdAt),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCash ? Colors.green.shade50 : primary.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCash ? 'Cash' : 'QRIS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCash ? Colors.green.shade700 : primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded item list
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildItemList(primary),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(Color primary) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_items == null || _items!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Tidak ada detail item', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text('Produk', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Harga', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 6),
          // Item rows
          ..._items!.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(item.productName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 1,
                  child: Text('${item.qty}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatRupiah(item.priceAtSale),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatRupiah(item.subtotal),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          )),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 6),
          // Total row
          Row(
            children: [
              const Expanded(flex: 4, child: SizedBox()),
              const Expanded(flex: 1, child: SizedBox()),
              Expanded(
                flex: 2,
                child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary)),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatRupiah(widget.transaction.total),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
