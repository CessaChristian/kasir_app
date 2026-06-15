import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/shift_report_repository.dart';

class ShiftDetailModal extends StatelessWidget {
  final ShiftSummary summary;

  const ShiftDetailModal({super.key, required this.summary});

  String _fmtCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  String _fmtDateTime(DateTime dt) =>
      DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt);

  @override
  Widget build(BuildContext context) {
    final shift = summary.shift;
    final primary = Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Detail Shift',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          // Info karyawan + waktu
          _infoCard([
            _row('Karyawan', summary.cashierName ?? '-'),
            _row('Mulai', _fmtDateTime(shift.startAt)),
            _row('Selesai',
                shift.endAt != null ? _fmtDateTime(shift.endAt!) : 'Masih aktif'),
            if (shift.endAt != null) ...[
              _row(
                'Durasi',
                _fmtDuration(shift.endAt!.difference(shift.startAt)),
              ),
            ],
          ]),

          const SizedBox(height: 12),

          // Ringkasan keuangan
          _sectionTitle('Ringkasan'),
          _infoCard([
            _row('Total Penjualan', _fmtCurrency(summary.totalRevenue),
                bold: true, color: primary),
            _row('Total Pengeluaran', _fmtCurrency(summary.totalExpenses),
                color: Colors.red.shade600),
            _row(
              'Bersih',
              _fmtCurrency(summary.totalRevenue - summary.totalExpenses),
              bold: true,
            ),
          ]),

          const SizedBox(height: 12),

          // Metode pembayaran
          _sectionTitle('Metode Pembayaran'),
          _infoCard([
            _row('Cash', '${summary.cashCount} transaksi'),
            _row('QRIS', '${summary.qrisCount} transaksi'),
            _row('Total', '${summary.transactionCount} transaksi', bold: true),
          ]),

          const SizedBox(height: 24),

          // Disclaimer (per spec D10 — shift summary selalu dynamic)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Data live — angka bisa berubah jika ada transaksi yang dihapus.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.amber.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}j ${m}m';
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
      );

  Widget _infoCard(List<Widget> rows) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: rows),
        ),
      );

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600)),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color ?? Colors.black87,
              ),
            ),
          ],
        ),
      );
}
