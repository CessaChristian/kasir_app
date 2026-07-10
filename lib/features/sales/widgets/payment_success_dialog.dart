import 'package:flutter/material.dart';
import '../../../utils/currency_formatter.dart';

/// Dialog sukses setelah pembayaran — menampilkan kembalian dengan BESAR
/// dan jelas supaya kasir tidak salah memberi kembalian.
///
/// Dialog ini sengaja tidak bisa di-dismiss dengan tap di luar
/// (barrierDismissible: false di caller) — kasir harus tap "Selesai"
/// setelah menyerahkan kembalian.
class PaymentSuccessDialog extends StatelessWidget {
  final int total;
  final int? cashReceived; // null = QRIS
  final String orderType; // 'dine_in' | 'take_away'

  const PaymentSuccessDialog({
    super.key,
    required this.total,
    required this.cashReceived,
    required this.orderType,
  });

  bool get _isCash => cashReceived != null;
  int get _change => _isCash ? cashReceived! - total : 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkmark animasi
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (_, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.green.shade600,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Transaksi Berhasil',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isCash ? 'Pembayaran Tunai' : 'Pembayaran QRIS',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 20),

            // Rincian
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _row('Total', 'Rp ${formatRupiah(total)}'),
                  if (_isCash) ...[
                    const SizedBox(height: 8),
                    _row('Tunai Diterima', 'Rp ${formatRupiah(cashReceived!)}'),
                  ],
                  const SizedBox(height: 8),
                  _row(
                    'Tipe Order',
                    orderType == 'dine_in' ? 'Dine In' : 'Take Away',
                  ),
                ],
              ),
            ),

            // KEMBALIAN — bagian paling penting, tampil besar
            if (_isCash) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: _change > 0
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _change > 0
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'KEMBALIAN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Rp ${formatRupiah(_change)}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: _change > 0
                              ? colorScheme.primary
                              : Colors.grey.shade700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (_change == 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Uang pas',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Selesai',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }
}
