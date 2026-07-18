import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/shift_report_repository.dart';
import '../widgets/shift_list_item.dart';
import '../widgets/shift_detail_modal.dart';
import '../widgets/date_range_filter.dart';
import '../../../data/business_context.dart';

/// Standalone page wrapper — dipertahankan untuk navigasi langsung
/// (misal deep link). Konten utama ada di [ShiftReportsView] yang juga
/// di-embed sebagai tab di halaman Laporan.
class ShiftReportsPage extends StatelessWidget {
  const ShiftReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Laporan Shift'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: const ShiftReportsView(),
    );
  }
}

/// Konten laporan shift (filter periode + summary + list) tanpa Scaffold —
/// bisa dipakai sebagai tab di halaman Laporan atau standalone page.
///
/// Permission gating dilakukan oleh CALLER (tab hanya muncul kalau user
/// punya 'view_shift_reports') — view ini tidak melakukan pop.
class ShiftReportsView extends StatefulWidget {
  const ShiftReportsView({super.key});

  @override
  State<ShiftReportsView> createState() => _ShiftReportsViewState();
}

class _ShiftReportsViewState extends State<ShiftReportsView> {
  final _repo = ShiftReportRepository();

  // Default period: 7 hari terakhir (normalized ke midnight, bukan jam saat ini)
  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _start = _ShiftReportsViewState._today.subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();

  List<ShiftSummary>? _summaries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Reload saat owner ganti business aktif
    BusinessContext.instance.addListener(_load);
  }

  @override
  void dispose() {
    BusinessContext.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
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

    return RefreshIndicator(
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
                    color: Colors.white,
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
