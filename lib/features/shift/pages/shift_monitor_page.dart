import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/auth/session_manager.dart';
import '../../reports/repositories/shift_report_repository.dart';
import '../../reports/widgets/date_range_filter.dart';
import 'shift_detail_page.dart';

/// Halaman khusus owner untuk MEMANTAU shift kasir (Kasir Pro style).
///
/// Menampilkan daftar shift yang dikelompokkan per hari (subheader), tiap
/// baris menampilkan ringkasan (kasir, waktu, jumlah transaksi, pendapatan).
/// Ketuk salah satu → [ShiftDetailPage] berisi detail + semua transaksinya.
///
/// Akses digating permission `view_shift_reports` oleh pemanggil. Cakupan:
/// user dengan `view_all_shifts` melihat semua kasir; tanpa itu hanya shift
/// miliknya sendiri.
///
/// CATATAN (Phase 2 / sync): saat ini di pemakaian multi-device nyata, device
/// owner belum memiliki data shift kasir sampai sinkronisasi database aktif.
/// Halaman ini otomatis benar begitu sync jalan.
class ShiftMonitorPage extends StatefulWidget {
  const ShiftMonitorPage({super.key});

  @override
  State<ShiftMonitorPage> createState() => _ShiftMonitorPageState();
}

class _ShiftMonitorPageState extends State<ShiftMonitorPage> {
  final _repo = ShiftReportRepository();

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _start = _ShiftMonitorPageState._today.subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();

  List<ShiftSummary>? _summaries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    // Scope: tanpa view_all_shifts → hanya shift sendiri.
    final canSeeAll =
        SessionManager.instance.hasCurrentPermission('view_all_shifts');
    final onlyUserId =
        canSeeAll ? null : SessionManager.instance.currentUserId;

    try {
      final summaries =
          await _repo.getShiftsForPeriod(_start, _end, onlyUserId: onlyUserId);
      if (mounted) {
        setState(() {
          _summaries = summaries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtCurrency(int amount) => NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  /// Kelompokkan summaries per hari (label + list), terurut hari terbaru dulu.
  List<MapEntry<String, List<ShiftSummary>>> _groupByDay(
      List<ShiftSummary> items) {
    final fmt = DateFormat('EEEE, d MMM yyyy', 'id_ID');
    final map = <String, List<ShiftSummary>>{};
    for (final s in items) {
      final key = fmt.format(s.shift.startAt);
      map.putIfAbsent(key, () => []).add(s);
    }
    // items sudah desc by startAt dari repo, jadi urutan key insertion = desc.
    return map.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final summaries = _summaries ?? [];
    final totalRevenue = summaries.fold(0, (s, x) => s + x.totalRevenue);
    final totalTx = summaries.fold(0, (s, x) => s + x.transactionCount);
    final groups = _groupByDay(summaries);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pantau Shift'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
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
                    // Summary card total
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Pendapatan',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(
                            _fmtCurrency(totalRevenue),
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: primary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${summaries.length} shift • $totalTx transaksi',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 4),
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
                hasScrollBody: false,
                child: Center(child: Text('Tidak ada shift dalam periode ini')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (_, gi) {
                    final group = groups[gi];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                          child: Text(
                            group.key,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        ...group.value.map((s) => _ShiftRow(
                              summary: s,
                              fmtCurrency: _fmtCurrency,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShiftDetailPage(summary: s),
                                ),
                              ),
                            )),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  final ShiftSummary summary;
  final String Function(int) fmtCurrency;
  final VoidCallback onTap;

  const _ShiftRow({
    required this.summary,
    required this.fmtCurrency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final shift = summary.shift;
    final isActive = shift.endAt == null;
    final timeFmt = DateFormat('HH:mm');
    final rangeStr = isActive
        ? 'Mulai ${timeFmt.format(shift.startAt)}'
        : '${timeFmt.format(shift.startAt)} – ${timeFmt.format(shift.endAt!)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    (summary.cashierName ?? '?').characters.first.toUpperCase(),
                    style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              summary.cashierName ?? 'Tanpa nama',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border:
                                    Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'Berjalan',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$rangeStr • ${summary.transactionCount} transaksi',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtCurrency(summary.totalRevenue),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: primary),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
