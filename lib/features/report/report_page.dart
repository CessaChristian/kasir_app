import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/db.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import 'package:fl_chart/fl_chart.dart';

import 'widgets/report_widgets.dart';
import 'widgets/employee_card.dart';
import 'monthly/monthly_report_tab.dart';
import 'services/report_export_service.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with SingleTickerProviderStateMixin {
  // Period mode
  bool _isMonthly = false;

  // Daily state
  DateTime _selectedDate = DateTime.now();
  ReportSummary? _report;
  List<EmployeeReportSummary> _employeeReports = [];

  // Monthly state
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  ReportSummary? _monthlyReport;
  List<DailyTrend> _dailyTrends = [];
  List<EmployeeReportSummary> _monthlyEmployeeReports = [];

  bool _isLoading = false;
  bool _isExporting = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);

    if (_isMonthly) {
      final results = await Future.wait([
        db.getMonthlyReportSummary(_selectedYear, _selectedMonth),
        db.getDailyTrends(_selectedYear, _selectedMonth),
        db.getEmployeeReportSummaryForRange(
          DateTime(_selectedYear, _selectedMonth, 1),
          DateTime(_selectedYear, _selectedMonth + 1, 1),
        ),
      ]);
      setState(() {
        _monthlyReport = results[0] as ReportSummary;
        _dailyTrends = results[1] as List<DailyTrend>;
        _monthlyEmployeeReports = results[2] as List<EmployeeReportSummary>;
        _isLoading = false;
      });
    } else {
      final results = await Future.wait([
        db.getReportSummary(_selectedDate),
        db.getEmployeeReportSummary(_selectedDate),
      ]);
      setState(() {
        _report = results[0] as ReportSummary;
        _employeeReports = results[1] as List<EmployeeReportSummary>;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportReport() async {
    // Determine the report data to export
    final report = _isMonthly ? _monthlyReport : _report;
    final employees = _isMonthly ? _monthlyEmployeeReports : _employeeReports;

    if (report == null || report.totalOrders == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diekspor')),
        );
      }
      return;
    }

    setState(() => _isExporting = true);
    try {
      await ReportExportService.exportReport(report, employees, isMonthly: _isMonthly);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _selectDate() async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: const Color(0xFF1A1A1A),
              surface: Colors.white,
              surfaceContainerHighest: primaryColor.withValues(alpha:0.05),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 8,
              shadowColor: primaryColor.withValues(alpha:0.2),
              headerBackgroundColor: primaryColor,
              headerForegroundColor: Colors.white,
              headerHeadlineStyle: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              headerHelpStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha:0.9),
              ),
              dayStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              todayBorder: BorderSide(color: primaryColor, width: 1.5),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return primaryColor;
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                if (states.contains(WidgetState.disabled)) return Colors.grey.shade400;
                return const Color(0xFF1A1A1A);
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              dayOverlayColor: WidgetStateProperty.all(primaryColor.withValues(alpha:0.1)),
              yearStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return const Color(0xFF1A1A1A);
              }),
              yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              yearOverlayColor: WidgetStateProperty.all(primaryColor.withValues(alpha:0.1)),
              surfaceTintColor: Colors.transparent,
              dividerColor: Colors.grey.shade200,
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.grey.shade600),
                textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              confirmButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(Colors.white),
                backgroundColor: WidgetStateProperty.all(primaryColor),
                textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 24, vertical: 10)),
                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadReport();
    }
  }

  void _showMonthPicker() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    int tempYear = _selectedYear;
    int tempMonth = _selectedMonth;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final months = [
              'Januari', 'Februari', 'Maret', 'April',
              'Mei', 'Juni', 'Juli', 'Agustus',
              'September', 'Oktober', 'November', 'Desember',
            ];
            final now = DateTime.now();

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Year selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => setModalState(() => tempYear--),
                          icon: const Icon(Icons.chevron_left_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                          ),
                        ),
                        Text(
                          '$tempYear',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: tempYear < now.year
                              ? () => setModalState(() => tempYear++)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Month grid
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final monthNum = index + 1;
                        final isSelected = tempMonth == monthNum;
                        final isFuture = tempYear == now.year && monthNum > now.month;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isFuture
                                ? null
                                : () {
                                    setModalState(() => tempMonth = monthNum);
                                  },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor
                                    : isFuture
                                        ? Colors.grey.shade50
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                months[index],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : isFuture
                                          ? Colors.grey.shade400
                                          : const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Confirm button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedYear = tempYear;
                            _selectedMonth = tempMonth;
                          });
                          _loadReport();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Pilih Periode', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDateDisplay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = DateTime(date.year, date.month, date.day);

    if (selectedDay == today) {
      return 'Hari Ini';
    } else if (selectedDay == yesterday) {
      return 'Kemarin';
    } else {
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
    }
  }

  String _formatMonthDisplay() {
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonth == now.month) {
      return 'Bulan Ini';
    }
    final date = DateTime(_selectedYear, _selectedMonth);
    return DateFormat('MMMM yyyy', 'id_ID').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Period toggle
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _PeriodToggleButton(
                label: 'Harian',
                isSelected: !_isMonthly,
                primaryColor: primaryColor,
                onTap: () {
                  if (_isMonthly) {
                    setState(() => _isMonthly = false);
                    _loadReport();
                  }
                },
              ),
              _PeriodToggleButton(
                label: 'Bulanan',
                isSelected: _isMonthly,
                primaryColor: primaryColor,
                onTap: () {
                  if (!_isMonthly) {
                    setState(() => _isMonthly = true);
                    _loadReport();
                  }
                },
              ),
            ],
          ),
        ),

        // Date/Month selector + Export button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              // Date/Month selector
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _isMonthly ? _showMonthPicker : _selectDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _isMonthly ? Icons.date_range_rounded : Icons.calendar_month_rounded,
                                color: primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Periode Laporan',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isMonthly ? _formatMonthDisplay() : _formatDateDisplay(_selectedDate),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Export button
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isExporting ? null : _exportReport,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _isExporting
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryColor,
                              ),
                            )
                          : Icon(
                              Icons.file_download_outlined,
                              color: primaryColor,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Tab Bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: const Color(0xFF1A1A1A),
            unselectedLabelColor: Colors.grey.shade500,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            padding: const EdgeInsets.all(4),
            tabs: const [
              Tab(text: 'Keseluruhan'),
              Tab(text: 'Per Karyawan'),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _isMonthly ? _buildMonthlyOverall() : _buildDailyOverall(),
                    _buildEmployeeReport(),
                  ],
                ),
        ),
      ],
    );
  }

  // ========================
  // DAILY OVERALL TAB
  // ========================
  Widget _buildDailyOverall() {
    final colorScheme = Theme.of(context).colorScheme;
    final report = _report;

    if (report == null || report.totalOrders == 0) {
      return ReportEmptyState(message: 'Belum ada penjualan pada ${_formatDateDisplay(_selectedDate).toLowerCase()}');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main summary cards
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  icon: Icons.receipt_long_rounded,
                  iconColor: colorScheme.primary,
                  iconBgColor: colorScheme.primary.withValues(alpha:0.1),
                  label: 'Total Pesanan',
                  value: '${report.totalOrders}',
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
                  value: 'Rp ${formatRupiah(report.totalIncome)}',
                  subtitle: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

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
                  orders: report.cashOrders,
                  total: report.cashTotal,
                ),
                Divider(height: 1, color: Colors.grey.shade200),
                PaymentMethodRow(
                  icon: Icons.qr_code_rounded,
                  iconColor: colorScheme.primary,
                  iconBgColor: colorScheme.primary.withValues(alpha:0.1),
                  label: 'QRIS',
                  orders: report.qrisOrders,
                  total: report.qrisTotal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Top Selling Products
          if (report.topProducts.isNotEmpty) ...[
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
                          report.topProducts.length,
                          (i) {
                            final product = report.topProducts[i];
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
                  ...List.generate(report.topProducts.length, (i) {
                    final product = report.topProducts[i];
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

  // ========================
  // MONTHLY OVERALL TAB
  // ========================
  Widget _buildMonthlyOverall() {
    final monthName = DateFormat('MMMM yyyy', 'id_ID').format(DateTime(_selectedYear, _selectedMonth));
    return MonthlyReportTab(
      report: _monthlyReport,
      dailyTrends: _dailyTrends,
      emptyMessage: 'Belum ada penjualan pada $monthName',
    );
  }

  // ========================
  // EMPLOYEE REPORT TAB
  // ========================
  Widget _buildEmployeeReport() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final reports = _isMonthly ? _monthlyEmployeeReports : _employeeReports;

    if (reports.isEmpty) {
      final periodLabel = _isMonthly
          ? DateFormat('MMMM yyyy', 'id_ID').format(DateTime(_selectedYear, _selectedMonth))
          : _formatDateDisplay(_selectedDate).toLowerCase();
      return ReportEmptyState(message: 'Belum ada aktivitas karyawan pada $periodLabel');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final employee = reports[index];
        return EmployeeCard(employee: employee, primaryColor: primaryColor);
      },
    );
  }
}

// ========================
// PERIOD TOGGLE BUTTON
// ========================
class _PeriodToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _PeriodToggleButton({
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? primaryColor : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}
