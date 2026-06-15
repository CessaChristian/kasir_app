import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../../../shared/auth/session_manager.dart';

class ActiveShiftCard extends StatefulWidget {
  const ActiveShiftCard({super.key});

  @override
  State<ActiveShiftCard> createState() => _ActiveShiftCardState();
}

class _ActiveShiftCardState extends State<ActiveShiftCard> {
  Shift? _shift;
  int _shiftRevenue = 0;
  int _shiftTxCount = 0;
  int _cashCount = 0;
  int _qrisCount = 0;
  bool _loading = true;
  Timer? _timer;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // LOW-1: refresh shift revenue/tx count saat ada transaksi baru
    _txSub = db.watchTransactions().listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final session = SessionManager.instance.currentSession;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final shifts = await (db.select(db.shifts)
          ..where((s) => s.id.equals(session.shiftId)))
        .get();

    final transactions = await (db.select(db.transactions)
          ..where((t) => t.shiftId.equals(session.shiftId))
          ..where((t) => t.deletedAt.isNull()))
        .get();

    final cashTxs = transactions.where((t) => t.paymentMethod == 'cash').length;
    final qrisTxs = transactions.where((t) => t.paymentMethod == 'qris').length;

    if (mounted) {
      setState(() {
        _shift = shifts.isNotEmpty ? shifts.first : null;
        _shiftRevenue = transactions.fold(0, (s, tx) => s + tx.total);
        _shiftTxCount = transactions.length;
        _cashCount = cashTxs;
        _qrisCount = qrisTxs;
        _loading = false;
      });
    }
  }

  String _formatDuration(DateTime startAt) {
    final diff = DateTime.now().difference(startAt);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  String _formatCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(amount);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_loading || _shift == null) return const SizedBox.shrink();

    final shift = _shift!;
    final duration = _formatDuration(shift.startAt);

    return Container(
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
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.schedule_rounded,
                    color: primaryColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Shift Aktif',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              // Duration chip — berkedip seperti live indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 12, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      duration,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 14),

          // Data row: mulai jam | tx count | pendapatan
          IntrinsicHeight(
            child: Row(
              children: [
                // Mulai shift
                Expanded(
                  child: _statColumn(
                    label: 'Mulai',
                    value: _formatTime(shift.startAt),
                    valueSize: 22,
                    color: Colors.grey.shade800,
                  ),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: Colors.grey.shade200),
                // Jumlah transaksi
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _statColumn(
                      label: 'Transaksi',
                      value: '$_shiftTxCount',
                      valueSize: 22,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: Colors.grey.shade200),
                // Pendapatan shift
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _statColumn(
                      label: 'Pendapatan Shift',
                      value: _formatCurrency(_shiftRevenue),
                      valueSize: 16,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),

          // Cash vs QRIS row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      'Cash: $_cashCount transaksi',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_rounded, size: 14, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text(
                      'QRIS: $_qrisCount transaksi',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statColumn({
    required String label,
    required String value,
    required double valueSize,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: valueSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
