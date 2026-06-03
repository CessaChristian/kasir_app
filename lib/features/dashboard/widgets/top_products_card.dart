import 'dart:async';
import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../../../data/models/top_product.dart';

class TopProductsCard extends StatefulWidget {
  const TopProductsCard({super.key});

  @override
  State<TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<TopProductsCard> {
  List<TopProduct> _products = [];
  bool _loading = true;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _load();
    // LOW-1: auto-refresh top products saat ada transaksi baru
    _txSub = db.watchTransactions().listen((_) {
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
    final products = await db.getTopSellingProducts(start, end, limit: 3);

    if (mounted) {
      setState(() {
        _products = products;
        _loading = false;
      });
    }
  }

  Widget _rankBadge(int rank, Color primaryColor) {
    final isFirst = rank == 1;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isFirst
            ? primaryColor.withValues(alpha: 0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isFirst ? primaryColor : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

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
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.emoji_events_rounded,
                    color: Colors.amber.shade700, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'Terlaris Hari Ini',
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
          else if (_products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 24, color: Colors.grey.shade300),
                    const SizedBox(height: 6),
                    Text(
                      'Belum ada\ntransaksi',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_products.length, (i) {
              final p = _products[i];
              final isLast = i == _products.length - 1;
              return Column(
                children: [
                  Row(
                    children: [
                      _rankBadge(i + 1, primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.productName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${p.totalQty}x',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast) ...[
                    const SizedBox(height: 8),
                    Divider(height: 1, color: Colors.grey.shade100),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }),
        ],
      ),
    );
  }
}
