import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/widgets/transaction_detail_sheet.dart';
import '../../reports/repositories/shift_report_repository.dart';

/// Detail satu shift: card utama ringkasan + daftar SEMUA transaksi shift itu.
/// Tiap transaksi bisa diketuk untuk melihat struk & itemnya.
class ShiftDetailPage extends StatefulWidget {
  final ShiftSummary summary;

  const ShiftDetailPage({super.key, required this.summary});

  @override
  State<ShiftDetailPage> createState() => _ShiftDetailPageState();
}

class _ShiftDetailPageState extends State<ShiftDetailPage> {
  final _repo = ShiftReportRepository();
  List<Transaction>? _transactions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txs = await _repo.getTransactionsForShift(widget.summary.shift.id);
    if (mounted) {
      setState(() {
        _transactions = txs;
        _loading = false;
      });
    }
  }

  String _fmtCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  String _formatDuration(DateTime start, DateTime? end) {
    final diff = (end ?? DateTime.now()).difference(start);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final s = widget.summary;
    final shift = s.shift;
    final isActive = shift.endAt == null;
    final netCash = s.totalRevenue - s.totalExpenses;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Detail Shift'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Card utama ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (s.cashierName ?? '?').characters.first.toUpperCase(),
                        style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.cashierName ?? 'Tanpa nama',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEEE, d MMM yyyy', 'id_ID')
                                .format(shift.startAt),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text('Berjalan',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey.shade100),
                const SizedBox(height: 14),

                _row('Waktu', isActive
                    ? '${DateFormat('HH:mm').format(shift.startAt)} – berjalan'
                    : '${DateFormat('HH:mm').format(shift.startAt)} – ${DateFormat('HH:mm').format(shift.endAt!)}'),
                _row('Durasi', _formatDuration(shift.startAt, shift.endAt)),
                const SizedBox(height: 8),
                Divider(height: 1, color: Colors.grey.shade100),
                const SizedBox(height: 12),

                _row('Pendapatan', _fmtCurrency(s.totalRevenue), strong: true,
                    valueColor: primary),
                _row('Jumlah transaksi', '${s.transactionCount}'),
                _row('Cash / QRIS',
                    '${s.cashCount} / ${s.qrisCount} transaksi'),
                _row('Pengeluaran', _fmtCurrency(s.totalExpenses)),
                const SizedBox(height: 8),
                Divider(height: 1, color: Colors.grey.shade100),
                const SizedBox(height: 12),
                _row('Kas bersih', _fmtCurrency(netCash),
                    strong: true,
                    valueColor: netCash >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade600),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'Transaksi (${s.transactionCount})',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if ((_transactions ?? []).isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Belum ada transaksi pada shift ini',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            ...(_transactions ?? []).map(_buildTxRow),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool strong = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxRow(Transaction tx) {
    final isCash = tx.paymentMethod == 'cash';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => TransactionDetailSheet(transaction: tx),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isCash ? Icons.payments_outlined : Icons.qr_code_rounded,
                  size: 18,
                  color: isCash ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 10),
                Text(
                  DateFormat('HH:mm').format(tx.createdAt),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Text(
                  isCash ? 'Cash' : 'QRIS',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const Spacer(),
                Text(
                  _fmtCurrency(tx.total),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
