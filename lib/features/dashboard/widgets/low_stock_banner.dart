import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../../products/repositories/product_repository.dart';
import '../../../data/app_database.dart';
import '../../../app/app_shell.dart';
import '../../../shared/constants/app_constants.dart';

class LowStockBanner extends StatelessWidget {
  const LowStockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: ProductRepository(db).watchProducts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final lowStock = snapshot.data!
            .where((p) => p.trackStock && p.stock != null && p.stock! <= AppConstants.lowStockThreshold)
            .toList()
          ..sort((a, b) => (a.stock ?? 0).compareTo(b.stock ?? 0));

        if (lowStock.isEmpty) return const SizedBox.shrink();

        final outOfStock = lowStock.where((p) => p.stock == 0).toList();
        final nearEmpty = lowStock.where((p) => p.stock! > 0).toList();

        final isUrgent = outOfStock.isNotEmpty;
        final bgColor =
            isUrgent ? const Color(0xFFFFF0F0) : const Color(0xFFFFF8E1);
        final borderColor =
            isUrgent ? const Color(0xFFFFCDD2) : const Color(0xFFFFD54F);
        final iconColor =
            isUrgent ? Colors.red.shade600 : Colors.amber.shade800;
        final iconBg =
            isUrgent ? Colors.red.shade50 : Colors.amber.shade100;
        final titleColor =
            isUrgent ? Colors.red.shade800 : Colors.amber.shade900;

        final preview = lowStock.take(3).toList();
        final remaining = lowStock.length - preview.length;

        return GestureDetector(
          onTap: () =>
              AppShell.globalKey.currentState?.navigateToPageByLabel('Produk'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isUrgent
                        ? Icons.error_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isUrgent
                                  ? '${outOfStock.length} Produk Habis, '
                                      '${nearEmpty.length} Hampir Habis'
                                  : '${lowStock.length} Produk Hampir Habis',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                            ),
                          ),
                          Text(
                            'Lihat',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right_rounded,
                              color: iconColor, size: 14),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...preview.map((p) {
                        final isEmpty = p.stock == 0;
                        final dotColor = isEmpty
                            ? Colors.red.shade500
                            : Colors.amber.shade700;
                        final stockLabel = isEmpty ? 'Habis' : 'sisa ${p.stock}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: titleColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isEmpty
                                      ? Colors.red.shade100
                                      : Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  stockLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: dotColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (remaining > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '+$remaining produk lainnya',
                            style: TextStyle(
                              fontSize: 11,
                              color: iconColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
