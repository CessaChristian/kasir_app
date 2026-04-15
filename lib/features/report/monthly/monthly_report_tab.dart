import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/app_database.dart';
import '../../../utils/currency_formatter.dart';
import '../widgets/report_widgets.dart';

/// Tab konten laporan bulanan (mode Keseluruhan)
class MonthlyReportTab extends StatelessWidget {
  final ReportSummary? report;
  final List<DailyTrend> dailyTrends;
  final String emptyMessage;

  const MonthlyReportTab({
    super.key,
    required this.report,
    required this.dailyTrends,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (report == null || report!.totalOrders == 0) {
      return ReportEmptyState(message: emptyMessage);
    }

    final r = report!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  icon: Icons.receipt_long_rounded,
                  iconColor: colorScheme.primary,
                  iconBgColor: colorScheme.primary.withValues(alpha:0.1),
                  label: 'Total Pesanan',
                  value: '${r.totalOrders}',
                  subtitle: 'transaksi',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: Colors.green.shade700,
                  iconBgColor: Colors.green.shade50,
                  label: 'Total Pemasukan',
                  value: 'Rp ${formatRupiah(r.totalIncome)}',
                  subtitle: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Daily trend chart
          if (dailyTrends.isNotEmpty) ...[
            const ReportSectionTitle('Tren Pendapatan Harian'),
            const SizedBox(height: 12),
            _DailyTrendChart(
              trends: dailyTrends,
              primaryColor: colorScheme.primary,
            ),
            const SizedBox(height: 24),
          ],

          // Payment method breakdown
          const ReportSectionTitle('Metode Pembayaran'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                PaymentMethodRow(
                  icon: Icons.payments_rounded,
                  iconColor: Colors.green.shade700,
                  iconBgColor: Colors.green.shade50,
                  label: 'Cash',
                  orders: r.cashOrders,
                  total: r.cashTotal,
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                PaymentMethodRow(
                  icon: Icons.qr_code_rounded,
                  iconColor: colorScheme.primary,
                  iconBgColor: colorScheme.primary.withValues(alpha:0.1),
                  label: 'QRIS',
                  orders: r.qrisOrders,
                  total: r.qrisTotal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Top products
          if (r.topProducts.isNotEmpty) ...[
            const ReportSectionTitle('Produk Terlaris'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 35,
                        sections: List.generate(
                          r.topProducts.length,
                          (i) {
                            final product = r.topProducts[i];
                            final isLarge = i == 0;
                            final colors = [
                              colorScheme.primary,
                              Colors.green,
                              Colors.orange,
                              Colors.purple,
                              Colors.teal,
                            ];
                            return PieChartSectionData(
                              color: colors[i % colors.length],
                              value: product.totalQty.toDouble(),
                              title: '${product.totalQty}',
                              radius: isLarge ? 55.0 : 45.0,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(r.topProducts.length, (i) {
                    final product = r.topProducts[i];
                    final colors = [
                      colorScheme.primary,
                      Colors.green,
                      Colors.orange,
                      Colors.purple,
                      Colors.teal,
                    ];
                    return ProductLegendItem(
                      color: colors[i % colors.length],
                      name: product.productName,
                      qty: product.totalQty,
                      total: product.totalSales,
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Line chart tren pendapatan harian
class _DailyTrendChart extends StatelessWidget {
  final List<DailyTrend> trends;
  final Color primaryColor;

  const _DailyTrendChart({required this.trends, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final maxIncome = trends.fold<int>(0, (max, t) => t.income > max ? t.income : max);
    final maxY = maxIncome > 0 ? (maxIncome * 1.2) : 100000.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        String text;
                        if (value >= 1000000) {
                          text = '${(value / 1000000).toStringAsFixed(1)}jt';
                        } else if (value >= 1000) {
                          text = '${(value / 1000).toStringAsFixed(0)}rb';
                        } else {
                          text = '${value.toInt()}';
                        }
                        return Text(
                          text,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _getBottomInterval(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                        return Text(
                          '${trends[idx].date.day}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (trends.length - 1).toDouble(),
                minY: 0,
                maxY: maxY.toDouble(),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt();
                        if (idx < 0 || idx >= trends.length) return null;
                        final trend = trends[idx];
                        return LineTooltipItem(
                          '${trend.date.day}/${trend.date.month}\n',
                          TextStyle(fontSize: 11, color: Colors.white.withValues(alpha:0.8)),
                          children: [
                            TextSpan(
                              text: 'Rp ${formatRupiah(trend.income)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      trends.length,
                      (i) => FlSpot(i.toDouble(), trends[i].income.toDouble()),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: primaryColor,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: trends[index].income > 0 ? 3 : 0,
                          color: primaryColor,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withValues(alpha:0.2),
                          primaryColor.withValues(alpha:0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Summary row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TrendStat(
                label: 'Rata-rata/hari',
                value: 'Rp ${formatRupiah(_averageIncome())}',
              ),
              _TrendStat(
                label: 'Hari tertinggi',
                value: _peakDayLabel(),
              ),
              _TrendStat(
                label: 'Hari aktif',
                value: '${trends.where((t) => t.orders > 0).length} hari',
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _getBottomInterval() {
    if (trends.length <= 10) return 1;
    if (trends.length <= 15) return 2;
    return 5;
  }

  int _averageIncome() {
    final activeDays = trends.where((t) => t.income > 0).toList();
    if (activeDays.isEmpty) return 0;
    return activeDays.fold<int>(0, (sum, t) => sum + t.income) ~/ activeDays.length;
  }

  String _peakDayLabel() {
    if (trends.isEmpty) return '-';
    final peak = trends.reduce((a, b) => a.income > b.income ? a : b);
    if (peak.income == 0) return '-';
    return DateFormat('d MMM', 'id_ID').format(peak.date);
  }
}

class _TrendStat extends StatelessWidget {
  final String label;
  final String value;

  const _TrendStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
