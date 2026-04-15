import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/dashed_divider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // Track which date sections are expanded (today expanded by default)
  final Set<String> _expandedDates = {};
  bool _initialized = false;
  
  // Month filter - null means show all
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: StreamBuilder<List<Transaction>>(
        stream: db.watchTransactions(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final allTransactions = snapshot.data!;

          if (allTransactions.isEmpty) {
            return _buildEmptyState();
          }
          
          // Get available months from transactions
          final availableMonths = _getAvailableMonths(allTransactions);
          
          // Filter transactions by selected month
          final transactions = _selectedMonth == null
              ? allTransactions
              : allTransactions.where((tx) {
                  return tx.createdAt.year == _selectedMonth!.year &&
                         tx.createdAt.month == _selectedMonth!.month;
                }).toList();

          // Group transactions by date
          final grouped = <String, List<Transaction>>{};
          for (final tx in transactions) {
            final dateKey = DateFormat('yyyy-MM-dd').format(tx.createdAt);
            grouped.putIfAbsent(dateKey, () => []).add(tx);
          }

          final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
          
          // Initialize: expand today's section by default
          if (!_initialized && sortedKeys.isNotEmpty) {
            _expandedDates.add(sortedKeys.first);
            _initialized = true;
          }
          
          // Calculate monthly total
          final monthlyTotal = transactions.fold<int>(0, (sum, tx) => sum + tx.total);

          return Column(
            children: [
              // Month filter
              _buildMonthFilter(availableMonths, monthlyTotal, transactions.length),
              
              // Transactions list
              Expanded(
                child: transactions.isEmpty
                    ? _buildNoTransactionsForMonth()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: sortedKeys.length,
                        itemBuilder: (context, index) {
                          final dateKey = sortedKeys[index];
                          final dayTransactions = grouped[dateKey]!;
                          final date = DateTime.parse(dateKey);
                          final isExpanded = _expandedDates.contains(dateKey);

                          // Calculate daily total
                          final dailyTotal = dayTransactions.fold<int>(
                            0, (sum, tx) => sum + tx.total);

                          return _buildDaySection(
                            date: date,
                            dateKey: dateKey,
                            transactions: dayTransactions,
                            dailyTotal: dailyTotal,
                            isExpanded: isExpanded,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  List<DateTime> _getAvailableMonths(List<Transaction> transactions) {
    final months = <String, DateTime>{};
    for (final tx in transactions) {
      final key = '${tx.createdAt.year}-${tx.createdAt.month.toString().padLeft(2, '0')}';
      months.putIfAbsent(key, () => DateTime(tx.createdAt.year, tx.createdAt.month));
    }
    final sortedMonths = months.values.toList()..sort((a, b) => b.compareTo(a));
    return sortedMonths;
  }
  
  Widget _buildMonthFilter(List<DateTime> availableMonths, int totalAmount, int transactionCount) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "Semua" chip
                _buildMonthChip(
                  label: 'Semua',
                  isSelected: _selectedMonth == null,
                  onTap: () => setState(() => _selectedMonth = null),
                ),
                const SizedBox(width: 8),
                // Month chips
                ...availableMonths.map((month) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildMonthChip(
                    label: DateFormat('MMM yyyy', 'id_ID').format(month),
                    isSelected: _selectedMonth?.year == month.year && 
                                _selectedMonth?.month == month.month,
                    onTap: () => setState(() => _selectedMonth = month),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Summary row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.insights_rounded, size: 18, color: primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedMonth == null 
                        ? 'Total Semua Waktu'
                        : 'Total ${DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Text(
                  'Rp ${formatRupiah(totalAmount)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Text(
                  ' • $transactionCount txn',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMonthChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha:0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
  
  Widget _buildNoTransactionsForMonth() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 32,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tidak Ada Transaksi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Belum ada transaksi di bulan ini',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
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
              Icons.receipt_long_outlined,
              size: 40,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Belum Ada Transaksi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Transaksi akan muncul di sini',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDaySection({
    required DateTime date,
    required String dateKey,
    required List<Transaction> transactions,
    required int dailyTotal,
    required bool isExpanded,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header - collapsible
        GestureDetector(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedDates.remove(dateKey);
              } else {
                _expandedDates.add(dateKey);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isExpanded ? primaryColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isExpanded ? primaryColor : Colors.grey.shade200,
              ),
              boxShadow: isExpanded
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha:0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isExpanded ? Colors.white.withValues(alpha:0.2) : primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: isExpanded ? Colors.white : primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(date),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isExpanded ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        '${transactions.length} transaksi',
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpanded ? Colors.white.withValues(alpha:0.8) : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Rp ${formatRupiah(dailyTotal)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isExpanded ? Colors.white : primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: isExpanded ? Colors.white : Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
        
        // Transaction cards (animated)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(
            children: [
              ...transactions.map((tx) => _TransactionCard(transaction: tx)),
              const SizedBox(height: 8),
            ],
          ),
          secondChild: const SizedBox.shrink(),
        ),
        
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final txDate = DateTime(date.year, date.month, date.day);

    if (txDate == today) {
      return 'Hari Ini';
    } else if (txDate == yesterday) {
      return 'Kemarin';
    } else {
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
    }
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isCash = transaction.paymentMethod == 'cash';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCash ? Colors.green.shade50 : primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCash ? Icons.payments_rounded : Icons.qr_code_rounded,
                    color: isCash ? Colors.green.shade600 : primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Rp ${formatRupiah(transaction.total)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCash ? Colors.green.shade50 : primaryColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCash ? 'Cash' : 'QRIS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isCash ? Colors.green.shade700 : primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(transaction.createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (isCash && transaction.cashReceived != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Bayar: Rp ${formatRupiah(transaction.cashReceived!)} • Kembali: Rp ${formatRupiah(transaction.change ?? 0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransactionDetailSheet(transaction: transaction),
    );
  }
}

class _TransactionDetailSheet extends StatefulWidget {
  final Transaction transaction;

  const _TransactionDetailSheet({required this.transaction});

  @override
  State<_TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<_TransactionDetailSheet> {
  List<TransactionItem>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await db.getTransactionItems(widget.transaction.id);
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
            padding: const EdgeInsets.only(top: 12),
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
                        '#${tx.id.substring(0, 8).toUpperCase()}',
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
                    // Store header
                    Icon(
                      Icons.storefront_rounded,
                      size: 36,
                      color: primaryColor,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppConstants.storeName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      AppConstants.storeAddress,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const DashedDivider(),
                    const SizedBox(height: 12),
                    
                    // Transaction Info
                    _buildInfoRow('Tanggal', DateFormat('dd/MM/yyyy HH:mm').format(tx.createdAt)),
                    const SizedBox(height: 6),
                    _buildInfoRow('No. Transaksi', '#${tx.id.substring(0, 8).toUpperCase()}'),
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
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${item.qty} x Rp ${formatRupiah(item.priceAtSale)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
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
                      Text(
                        'Tidak ada item',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    
                    const SizedBox(height: 8),
                    const DashedDivider(),
                    const SizedBox(height: 12),
                    
                    // Total Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha:0.08),
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
                      _buildInfoRow('Bayar (Cash)', 'Rp ${formatRupiah(tx.cashReceived!)}'),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kembalian',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
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
                          Text(
                            'Metode Pembayaran',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha:0.1),
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
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
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
  
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }
}
