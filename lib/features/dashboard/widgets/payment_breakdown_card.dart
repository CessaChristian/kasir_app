import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/db.dart';
import '../../sales/repositories/sales_repository.dart';

class PaymentBreakdownCard extends StatefulWidget {
  const PaymentBreakdownCard({super.key});

  @override
  State<PaymentBreakdownCard> createState() => _PaymentBreakdownCardState();
}

class _PaymentBreakdownCardState extends State<PaymentBreakdownCard> {
  final _salesRepo = SalesRepository(db);
  int _cashTotal = 0;
  int _cashCount = 0;
  int _qrisTotal = 0;
  int _qrisCount = 0;
  bool _loading = true;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _load();
    // LOW-1: auto-refresh saat ada transaksi baru
    _txSub = _salesRepo.watchTransactions().listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final txs = await _salesRepo.getTransactionsByDateRange(start, end);

    final cash = txs.where((t) => t.paymentMethod == 'cash').toList();
    final qris = txs.where((t) => t.paymentMethod == 'qris').toList();

    if (mounted) {
      setState(() {
        _cashTotal = cash.fold(0, (s, t) => s + t.total);
        _cashCount = cash.length;
        _qrisTotal = qris.fold(0, (s, t) => s + t.total);
        _qrisCount = qris.length;
        _loading = false;
      });
    }
  }

  String _fmt(int amount) => NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(amount);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(Icons.payment_rounded, color: primaryColor, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'Pembayaran',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),

          if (_loading)
            Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: primaryColor),
              ),
            )
          else ...[
            _paymentRow(
              icon: Icons.payments_rounded,
              label: 'Cash',
              total: _cashTotal,
              count: _cashCount,
              color: Colors.green.shade600,
              bgColor: Colors.green.shade50,
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 10),
            _paymentRow(
              icon: Icons.qr_code_rounded,
              label: 'QRIS',
              total: _qrisTotal,
              count: _qrisCount,
              color: primaryColor,
              bgColor: primaryColor.withValues(alpha: 0.08),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentRow({
    required IconData icon,
    required String label,
    required int total,
    required int count,
    required Color color,
    required Color bgColor,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              Text(
                _fmt(total),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$count trx',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}
