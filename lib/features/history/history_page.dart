import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/widgets/transaction_detail_sheet.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/widgets/app_toast.dart';

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
  DateTime? _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<List<Transaction>>(
        stream: db.watchTransactions(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateWidget(
              title: 'Gagal memuat riwayat',
              message: 'Terjadi kesalahan saat mengambil data transaksi.',
              onRetry: () => setState(() {}),
            );
          }

          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final allTransactions = snapshot.data ?? [];

          if (allTransactions.isEmpty) {
            return _buildEmptyState();
          }
          
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
              _buildMonthFilter(monthlyTotal, transactions.length),
              
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

  String _formatMonthDisplay() {
    if (_selectedMonth == null) return 'Semua Waktu';
    final now = DateTime.now();
    if (_selectedMonth!.year == now.year && _selectedMonth!.month == now.month) {
      return 'Bulan Ini';
    }
    return DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth!);
  }

  void _showMonthPicker() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    int tempYear = _selectedMonth?.year ?? DateTime.now().year;
    int tempMonth = _selectedMonth?.month ?? DateTime.now().month;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final months = [
              'Januari', 'Februari', 'Maret', 'April',
              'Mei', 'Juni', 'Juli', 'Agustus',
              'September', 'Oktober', 'November', 'Desember',
            ];
            final now = DateTime.now();

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Year selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => setModalState(() => tempYear--),
                          icon: const Icon(Icons.chevron_left_rounded),
                          style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                        ),
                        Text(
                          '$tempYear',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: tempYear < now.year
                              ? () => setModalState(() => tempYear++)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                        ),
                      ],
                    ),
                  ),
                  // Month grid
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final monthNum = index + 1;
                        final isSelected = tempMonth == monthNum;
                        final isFuture = tempYear == now.year && monthNum > now.month;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isFuture
                                ? null
                                : () => setModalState(() => tempMonth = monthNum),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor
                                    : isFuture
                                        ? Colors.grey.shade50
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                months[index],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : isFuture
                                          ? Colors.grey.shade400
                                          : const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Row(
                      children: [
                        // Semua Waktu button
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedMonth = null);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Semua Waktu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Pilih Periode button
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedMonth = DateTime(tempYear, tempMonth));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Pilih Periode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMonthFilter(int totalAmount, int transactionCount) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          // Period picker button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showMonthPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.date_range_rounded, color: primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Periode Riwayat',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatMonthDisplay(),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Summary card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.insights_rounded, size: 17, color: primaryColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedMonth == null
                        ? 'Total Semua Waktu'
                        : 'Total ${DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth!)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rp ${formatRupiah(totalAmount)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      '$transactionCount transaksi',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
  
  Future<void> _confirmDeleteTransaction(Transaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tindakan ini akan:'),
            SizedBox(height: 8),
            Text('• Mengembalikan produk ke stok'),
            Text('• Mengurangi total penjualan'),
            Text('• Mengubah laporan shift'),
            SizedBox(height: 8),
            Text('Tidak dapat di-undo.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Transaksi'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await db.softDeleteTransaction(tx.id);
      if (mounted) AppToast.success(context, 'Transaksi berhasil dihapus');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal hapus: $e');
    }
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
              ...transactions.map((tx) {
                final canDelete = SessionManager.instance.canPerformActionOnRecord(
                  anyPermission: 'delete_any_transaction',
                  ownPermission: 'delete_own_transaction',
                  recordOwnerId: tx.cashierUserId,
                );
                return _TransactionCard(
                  transaction: tx,
                  onDelete: canDelete ? () => _confirmDeleteTransaction(tx) : null,
                );
              }),
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
  final VoidCallback? onDelete;

  const _TransactionCard({required this.transaction, this.onDelete});

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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDelete != null)
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.red.shade400),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade400,
                    ),
                  ],
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
      builder: (_) => TransactionDetailSheet(transaction: transaction),
    );
  }
}

