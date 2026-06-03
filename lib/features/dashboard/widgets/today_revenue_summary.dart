import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/db.dart';

class TodayRevenueSummary extends StatefulWidget {
  const TodayRevenueSummary({super.key});

  @override
  State<TodayRevenueSummary> createState() => _TodayRevenueSummaryState();
}

class _TodayRevenueSummaryState extends State<TodayRevenueSummary> {
  int _todayRevenue = 0;
  int _yesterdayRevenue = 0;
  int _transactionCount = 0;
  bool _isLoading = true;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _loadTodayRevenue();
    // LOW-1: Re-load setiap kali ada perubahan di tabel transactions
    // (insert dari createSale, update, dll) — badge "LIVE" jadi benar.
    _txSub = db.watchTransactions().listen((_) {
      if (mounted) _loadTodayRevenue();
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTodayRevenue() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));

      final todayTx =
          await db.getTransactionsByDateRange(todayStart, todayEnd);
      final yesterdayTx =
          await db.getTransactionsByDateRange(yesterdayStart, todayStart);

      if (mounted) {
        setState(() {
          _todayRevenue = todayTx.fold<int>(0, (s, tx) => s + tx.total);
          _yesterdayRevenue =
              yesterdayTx.fold<int>(0, (s, tx) => s + tx.total);
          _transactionCount = todayTx.length;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      // I3: Hanya log di debug build — production tetap silent (no leak).
      assert(() {
        debugPrint('TodayRevenueSummary error: $e\n$stack');
        return true;
      }());
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTrendBadge() {
    if (_yesterdayRevenue == 0 && _todayRevenue == 0) return const SizedBox.shrink();

    if (_yesterdayRevenue == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_new_rounded, size: 13, color: Colors.blue.shade400),
          const SizedBox(width: 3),
          Text(
            'Hari baru',
            style: TextStyle(fontSize: 10, color: Colors.blue.shade400, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    final diff = _todayRevenue - _yesterdayRevenue;
    final percent = (diff / _yesterdayRevenue * 100).abs().toStringAsFixed(0);
    final isUp = diff >= 0;
    final color = isUp ? Colors.green.shade600 : Colors.red.shade500;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '$percent% dari kemarin',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  void _showDetailSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title row
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.trending_up_rounded, color: Colors.green.shade600, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pendapatan Hari Ini',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                    ),
                    Text(
                      DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.payments_rounded,
                    label: 'Total Pendapatan',
                    value: _formatCurrency(_todayRevenue),
                    color: Colors.green.shade600,
                    bgColor: Colors.green.shade50,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.receipt_long_rounded,
                    label: 'Jumlah Transaksi',
                    value: '$_transactionCount',
                    color: colorScheme.primary,
                    bgColor: colorScheme.primary.withValues(alpha: 0.06),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Average
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rata-rata per Transaksi',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _transactionCount > 0
                            ? _formatCurrency(_todayRevenue ~/ _transactionCount)
                            : 'Rp 0',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _showDetailSheet,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Icon(Icons.trending_up_rounded, color: Colors.green.shade600, size: 26),
            ),
            const SizedBox(width: 14),

            // Revenue info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Pendapatan Hari Ini',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade100),
                        ),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _isLoading
                      ? Container(
                          height: 22,
                          width: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TweenAnimationBuilder<int>(
                              tween: IntTween(begin: 0, end: _todayRevenue),
                              duration: const Duration(milliseconds: 1000),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, child) => Text(
                                _formatCurrency(v),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _buildTrendBadge(),
                          ],
                        ),
                ],
              ),
            ),

            // Transaction count badge — kompak tanpa label teks
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 14, color: colorScheme.primary),
                    const SizedBox(height: 2),
                    Text(
                      '$_transactionCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}
