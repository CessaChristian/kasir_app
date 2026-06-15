import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/shift_report_repository.dart';

class ShiftListItem extends StatelessWidget {
  final ShiftSummary summary;
  final VoidCallback onTap;

  const ShiftListItem({
    super.key,
    required this.summary,
    required this.onTap,
  });

  String _fmtCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(amount);

  String _fmtDate(DateTime dt) =>
      DateFormat('dd MMM, HH:mm', 'id_ID').format(dt);

  @override
  Widget build(BuildContext context) {
    final shift = summary.shift;
    final isActive = shift.endAt == null;
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              isActive ? primary.withValues(alpha: 0.1) : Colors.grey.shade100,
          child: Icon(
            isActive ? Icons.play_circle_outline : Icons.check_circle_outline,
            color: isActive ? primary : Colors.grey.shade500,
          ),
        ),
        title: Text(
          summary.cashierName ?? 'Kasir',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${_fmtDate(shift.startAt)}${shift.endAt != null ? ' — ${_fmtDate(shift.endAt!)}' : ' (aktif)'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _fmtCurrency(summary.totalRevenue),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: primary,
              ),
            ),
            Text(
              '${summary.transactionCount} transaksi',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
