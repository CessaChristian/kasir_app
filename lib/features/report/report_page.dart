import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/db.dart';
import '../../shared/widgets/app_toast.dart';
import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../../shared/auth/session_manager.dart';
import 'package:fl_chart/fl_chart.dart';

import 'widgets/report_widgets.dart';
import 'widgets/employee_card.dart';
import 'monthly/monthly_report_tab.dart';
import 'services/report_export_service.dart';
import '../../shared/widgets/transaction_detail_sheet.dart';
import '../reports/pages/shift_reports_page.dart';

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
  bool _hasLoadError = false;
  bool _filterExpanded = true;

  late TabController _tabController;

  bool get _isOwner =>
      SessionManager.instance.hasPermission('manage_cashiers');

  // Tab "Shift" hanya untuk user dengan permission view_shift_reports
  // (menggantikan menu "Laporan Shift" terpisah yang membingungkan).
  bool get _canViewShiftReports =>
      SessionManager.instance.hasCurrentPermission('view_shift_reports');

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _canViewShiftReports ? 3 : 2, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
    });
    try {
      if (_isMonthly) {
        final start = DateTime(_selectedYear, _selectedMonth, 1);
        final end = DateTime(_selectedYear, _selectedMonth + 1, 1);

        final report = await db.getMonthlyReportSummary(_selectedYear, _selectedMonth);
        final trends = await db.getDailyTrends(_selectedYear, _selectedMonth);
        final employees = await db.getEmployeeReportSummaryForRange(start, end);

        if (!mounted) return;
        setState(() {
          _monthlyReport = report;
          _dailyTrends = trends;
          _monthlyEmployeeReports = employees;
          _isLoading = false;
        });
      } else {
        final report = await db.getReportSummary(_selectedDate);
        final employees = await db.getEmployeeReportSummary(_selectedDate);

        if (!mounted) return;
        setState(() {
          _report = report;
          _employeeReports = employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _hasLoadError = true; });
    }
  }

  Future<void> _exportReport() async {
    // Determine the report data to export
    final report = _isMonthly ? _monthlyReport : _report;
    final employees = _isMonthly ? _monthlyEmployeeReports : _employeeReports;

    if (report == null || report.totalOrders == 0) {
      if (mounted) AppToast.warning(context, 'Tidak ada data untuk diekspor');
      return;
    }

    setState(() => _isExporting = true);
    try {
      await ReportExportService.exportReport(report, employees, isMonthly: _isMonthly);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal export: $e');
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
                    margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
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
        // Collapsible filter: period toggle + date picker
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _filterExpanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Period toggle — sliding indicator
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Stack(
                        children: [
                          // Sliding white indicator
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            alignment: _isMonthly
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Labels di atas indicator
                          Row(
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
                  ],
                )
              : const SizedBox.shrink(),
        ),

        // Tab Bar + tombol buka/tutup filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
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
                    tabs: [
                      const Tab(text: 'Keseluruhan'),
                      const Tab(text: 'Per Karyawan'),
                      if (_canViewShiftReports) const Tab(text: 'Shift'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _filterExpanded = !_filterExpanded),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AnimatedRotation(
                      turns: _filterExpanded ? 0 : 0.5,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _hasLoadError
                  ? _buildErrorState()
                  : TabBarView(
                  controller: _tabController,
                  children: [
                    _isMonthly ? _buildMonthlyOverall() : _buildDailyOverall(),
                    _buildEmployeeReport(),
                    if (_canViewShiftReports) const ShiftReportsView(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat laporan',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Terjadi kesalahan saat mengambil data dari database.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Muat Ulang'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required int value,
    required bool isPositive,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
          Text(
            '${isPositive ? '' : '- '}Rp ${formatRupiah(value.abs())}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isPositive ? Colors.green.shade700 : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeCard({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 14, color: Colors.grey.shade400),
                ],
              ],
            ),
          ),
        ),
      ),
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

          // Expense & Net Income
          if (report.totalExpenses > 0) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildFinanceRow(
                    icon: Icons.trending_up_rounded,
                    iconColor: Colors.green.shade700,
                    iconBg: Colors.green.shade50,
                    label: 'Pemasukan',
                    value: report.totalIncome,
                    isPositive: true,
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _buildFinanceRow(
                    icon: Icons.trending_down_rounded,
                    iconColor: Colors.red.shade600,
                    iconBg: Colors.red.shade50,
                    label: 'Pengeluaran',
                    value: report.totalExpenses,
                    isPositive: false,
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _buildFinanceRow(
                    icon: Icons.account_balance_rounded,
                    iconColor: colorScheme.primary,
                    iconBg: colorScheme.primary.withValues(alpha: 0.1),
                    label: 'Laba Bersih',
                    value: report.netIncome,
                    isPositive: report.netIncome >= 0,
                    isBold: true,
                  ),
                  if (_isOwner && report.totalExpenses > 0) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    InkWell(
                      onTap: _showDailyExpenseSheet,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Lihat detail pengeluaran per kasir',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
          const SizedBox(height: 20),

          // Order type breakdown
          const ReportSectionTitle('Tipe Pesanan'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildOrderTypeCard(
                icon: Icons.restaurant_rounded,
                label: 'Dine In',
                count: report.dineInOrders,
                color: colorScheme.primary,
                onTap: report.dineInOrders > 0
                    ? () => _showOrderTypeSheet('dine_in', 'Dine In',
                        colorScheme.primary, Icons.restaurant_rounded)
                    : null,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildOrderTypeCard(
                icon: Icons.shopping_bag_rounded,
                label: 'Take Away',
                count: report.takeAwayOrders,
                color: Colors.orange,
                onTap: report.takeAwayOrders > 0
                    ? () => _showOrderTypeSheet('take_away', 'Take Away',
                        Colors.orange, Icons.shopping_bag_rounded)
                    : null,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildOrderTypeCard(
                icon: Icons.delivery_dining_rounded,
                label: 'Delivery',
                count: report.deliveryOrders,
                color: Colors.green.shade600,
                onTap: report.deliveryOrders > 0
                    ? () => _showOrderTypeSheet('delivery', 'Delivery',
                        Colors.green.shade600, Icons.delivery_dining_rounded)
                    : null,
              )),
            ],
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
    final monthName = DateFormat('MMMM yyyy', 'id_ID')
        .format(DateTime(_selectedYear, _selectedMonth));

    // Tombol "Lihat Detail Pengeluaran" hanya muncul jika owner & ada pengeluaran
    // Data dimuat on-demand saat sheet dibuka — tidak memberatkan load awal
    final Widget? expenseSection =
        (_isOwner && (_monthlyReport?.totalExpenses ?? 0) > 0)
            ? Column(
                children: [
                  Divider(height: 1, color: Colors.grey.shade200),
                  InkWell(
                    onTap: _showMonthlyExpenseSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Lihat detail pengeluaran per kasir',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : null;

    final colorScheme = Theme.of(context).colorScheme;

    return MonthlyReportTab(
      report: _monthlyReport,
      dailyTrends: _dailyTrends,
      emptyMessage: 'Belum ada penjualan pada $monthName',
      expenseSection: expenseSection,
      onOrderTypeTap: (orderType) {
        final IconData icon = orderType == 'dine_in'
            ? Icons.restaurant_rounded
            : orderType == 'take_away'
                ? Icons.shopping_bag_rounded
                : Icons.delivery_dining_rounded;
        final Color color = orderType == 'dine_in'
            ? colorScheme.primary
            : orderType == 'take_away'
                ? Colors.orange
                : Colors.green.shade600;
        final String label = orderType == 'dine_in'
            ? 'Dine In'
            : orderType == 'take_away'
                ? 'Take Away'
                : 'Delivery';
        _showOrderTypeSheet(orderType, label, color, icon);
      },
    );
  }

  void _showOrderTypeSheet(
    String orderType,
    String label,
    Color color,
    IconData icon,
  ) {
    final bool isMonthly = _isMonthly;
    final DateTime startDate = isMonthly
        ? DateTime(_selectedYear, _selectedMonth, 1)
        : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final DateTime endDate = isMonthly
        ? DateTime(_selectedYear, _selectedMonth + 1, 1)
        : startDate.add(const Duration(days: 1));
    final String periodLabel = isMonthly
        ? DateFormat('MMMM yyyy', 'id_ID')
            .format(DateTime(_selectedYear, _selectedMonth))
        : _formatDateDisplay(_selectedDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderTypeSheet(
        orderType: orderType,
        label: label,
        color: color,
        icon: icon,
        startDate: startDate,
        endDate: endDate,
        periodLabel: periodLabel,
      ),
    );
  }

  void _showDailyExpenseSheet() {
    final start = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end = start.add(const Duration(days: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseDetailSheet(
        periodLabel: _formatDateDisplay(_selectedDate),
        totalExpenses: _report?.totalExpenses ?? 0,
        startDate: start,
        endDate: end,
      ),
    );
  }

  void _showMonthlyExpenseSheet() {
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = DateTime(_selectedYear, _selectedMonth + 1, 1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseDetailSheet(
        periodLabel: DateFormat('MMMM yyyy', 'id_ID')
            .format(DateTime(_selectedYear, _selectedMonth)),
        totalExpenses: _monthlyReport?.totalExpenses ?? 0,
        startDate: start,
        endDate: end,
      ),
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
// EXPENSE DETAIL SHEET
// ========================
class _ExpenseDetailSheet extends StatefulWidget {
  final String periodLabel;
  final int totalExpenses;
  final DateTime startDate;
  final DateTime endDate;

  const _ExpenseDetailSheet({
    required this.periodLabel,
    required this.totalExpenses,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<_ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<_ExpenseDetailSheet> {
  List<ExpenseEntry>? _entries;
  bool _loading = true;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await db.getAllExpensesForOwner(
      startDate: widget.startDate,
      endDate: widget.endDate,
    );
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.red.shade400, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detail Pengeluaran',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                      ),
                      Text(
                        widget.periodLabel,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    Text(
                      'Rp ${formatRupiah(widget.totalExpenses)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: colorScheme.primary, strokeWidth: 2),
                    ),
                  )
                : (_entries == null || _entries!.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('Tidak ada pengeluaran pada bulan ini',
                                  style: TextStyle(color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      )
                    : _buildGroupedList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    // Kelompokkan per username
    final grouped = <String, List<ExpenseEntry>>{};
    for (final e in _entries!) {
      grouped.putIfAbsent(e.username, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      shrinkWrap: true,
      children: grouped.entries.map((entry) {
        final username = entry.key;
        final expenses = entry.value;
        final total = expenses.fold<int>(0, (s, e) => s + e.expense.amount);
        final isExpanded = _expanded.contains(username);
        return _buildCashierGroup(username, expenses, total, isExpanded);
      }).toList(),
    );
  }

  Widget _buildCashierGroup(
    String username,
    List<ExpenseEntry> expenses,
    int total,
    bool isExpanded,
  ) {
    final timeFmt = DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header kasir — tappable
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              if (isExpanded) {
                _expanded.remove(username);
              } else {
                _expanded.add(username);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.person_outline_rounded,
                        size: 20, color: Colors.red.shade400),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${expenses.length} pengeluaran',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Rp ${formatRupiah(total)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),

          // List item pengeluaran (visible saat expanded)
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: expenses.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.red.shade300,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.expense.description,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF1A1A1A)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeFmt.format(entry.expense.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Rp ${formatRupiah(entry.expense.amount)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.red.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
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
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 40,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? primaryColor : Colors.grey.shade500,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================
// ORDER TYPE SHEET
// ========================
class _OrderTypeSheet extends StatefulWidget {
  final String orderType;
  final String label;
  final Color color;
  final IconData icon;
  final DateTime startDate;
  final DateTime endDate;
  final String periodLabel;

  const _OrderTypeSheet({
    required this.orderType,
    required this.label,
    required this.color,
    required this.icon,
    required this.startDate,
    required this.endDate,
    required this.periodLabel,
  });

  @override
  State<_OrderTypeSheet> createState() => _OrderTypeSheetState();
}

class _OrderTypeSheetState extends State<_OrderTypeSheet> {
  List<Transaction>? _transactions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final all = await db.getTransactionsByDateRange(
        widget.startDate, widget.endDate);
    final filtered =
        all.where((tx) => tx.orderType == widget.orderType).toList();
    if (mounted) {
      setState(() {
        _transactions = filtered;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(widget.icon, color: widget.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A)),
                      ),
                      Text(
                        widget.periodLabel,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                if (_transactions != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      Text(
                        '${_transactions!.length} pesanan',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: widget.color,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Content
          Flexible(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: colorScheme.primary, strokeWidth: 2),
                    ),
                  )
                : (_transactions == null || _transactions!.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.icon,
                                  size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'Tidak ada pesanan ${widget.label.toLowerCase()}',
                                style:
                                    TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('d MMM', 'id_ID');
    final isMultiDay =
        widget.endDate.difference(widget.startDate).inDays > 1;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      shrinkWrap: true,
      itemCount: _transactions!.length,
      itemBuilder: (context, i) {
        final tx = _transactions![i];
        final isCash = tx.paymentMethod == 'cash';
        final payColor = isCash ? Colors.green.shade600 : widget.color;
        final payIcon =
            isCash ? Icons.payments_rounded : Icons.qr_code_rounded;
        final payLabel = isCash ? 'Cash' : 'QRIS';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) =>
                    TransactionDetailSheet(transaction: tx),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Payment icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: payColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(payIcon, color: payColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rp ${formatRupiah(tx.total)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isMultiDay
                                ? '${dateFmt.format(tx.createdAt)} · ${timeFmt.format(tx.createdAt)}'
                                : timeFmt.format(tx.createdAt),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    // Payment badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: payColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        payLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: payColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
