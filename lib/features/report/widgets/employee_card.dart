import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/app_database.dart';
import '../../../utils/currency_formatter.dart';
import 'employee_detail_sheet.dart';

/// Kartu karyawan yang bisa di-expand
class EmployeeCard extends StatefulWidget {
  final EmployeeReportSummary employee;
  final Color primaryColor;

  const EmployeeCard({super.key, required this.employee, required this.primaryColor});

  @override
  State<EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends State<EmployeeCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final primaryColor = widget.primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isExpanded ? primaryColor : Colors.grey.shade200),
        boxShadow: _isExpanded
            ? [BoxShadow(color: primaryColor.withValues(alpha:0.15), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        e.username[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.username,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${e.totalTransactions} transaksi • ${e.shifts.length} shift',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rp ${formatRupiah(e.totalIncome)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: 8),
                  
                  // Payment breakdown
                  Row(
                    children: [
                      _MiniStat(
                        icon: Icons.payments_rounded,
                        iconColor: Colors.green.shade700,
                        label: 'Cash',
                        value: 'Rp ${formatRupiah(e.cashTotal)}',
                        subtitle: '${e.cashOrders} transaksi',
                      ),
                      const SizedBox(width: 12),
                      _MiniStat(
                        icon: Icons.qr_code_rounded,
                        iconColor: primaryColor,
                        label: 'QRIS',
                        value: 'Rp ${formatRupiah(e.qrisTotal)}',
                        subtitle: '${e.qrisOrders} transaksi',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Shifts
                  Text(
                    'Riwayat Shift',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  ...e.shifts.map((shift) => _ShiftItem(shift: shift, primaryColor: primaryColor)),
                  
                  const SizedBox(height: 16),
                  
                  // View Detail Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => showEmployeeDetailSheet(context, e),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Lihat Detail Lengkap'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;

  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftItem extends StatelessWidget {
  final ShiftInfo shift;
  final Color primaryColor;

  const _ShiftItem({required this.shift, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final startTime = DateFormat('HH:mm').format(shift.startAt);
    final endTime = shift.endAt != null ? DateFormat('HH:mm').format(shift.endAt!) : 'Aktif';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, size: 16, color: primaryColor),
          const SizedBox(width: 8),
          Text(
            '$startTime - $endTime',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Text(
            '${shift.transactionCount} txn',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Text(
            'Rp ${formatRupiah(shift.totalIncome)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryColor),
          ),
        ],
      ),
    );
  }
}
