import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/shift_report_repository.dart';
import '../widgets/shift_list_item.dart';
import '../widgets/shift_detail_modal.dart';
import '../widgets/date_range_filter.dart';
import '../../../shared/auth/session_manager.dart';

class ShiftReportsPage extends StatefulWidget {
  const ShiftReportsPage({super.key});

  @override
  State<ShiftReportsPage> createState() => _ShiftReportsPageState();
}

class _ShiftReportsPageState extends State<ShiftReportsPage> {
  final _repo = ShiftReportRepository();

  // Default period: 7 hari terakhir
  DateTime _start = DateTime.now().subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();

  List<ShiftSummary>? _summaries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    if (!SessionManager.instance.hasCurrentPermission('view_shift_reports')) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summaries = await _repo.getShiftsForPeriod(_start, _end);
      if (mounted) {
        setState(() {
          _summaries = summaries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final summaries = _summaries ?? [];
    final totalRevenue = summaries.fold(0, (s, x) => s + x.totalRevenue);
    final totalTx = summaries.fold(0, (s, x) => s + x.transactionCount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: AppBar(
        title: const Text('Laporan Shift'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Disclaimer
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Data live — angka bisa berubah jika ada transaksi yang dihapus.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Summary card total
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Pendapatan',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _fmtCurrency(totalRevenue),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${summaries.length} shift • $totalTx transaksi',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Filter periode
                    DateRangeFilter(
                      startDate: _start,
                      endDate: _end,
                      onChanged: (s, e) {
                        setState(() {
                          _start = s;
                          _end = e;
                        });
                        _load();
                      },
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Daftar Shift:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (summaries.isEmpty)
              const SliverFillRemaining(
                child: Center(
                    child: Text('Tidak ada shift dalam periode ini')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => ShiftListItem(
                      summary: summaries[i],
                      onTap: () => _showDetail(summaries[i]),
                    ),
                    childCount: summaries.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetail(ShiftSummary summary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShiftDetailModal(summary: summary),
    );
  }
}
