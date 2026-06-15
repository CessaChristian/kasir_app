import 'package:drift/drift.dart' hide isNull, isNotNull;
import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../data/business_context.dart';

class ShiftSummary {
  final Shift shift;
  final String? cashierName;
  final int totalRevenue;
  final int transactionCount;
  final int cashCount;
  final int qrisCount;
  final int totalExpenses;

  const ShiftSummary({
    required this.shift,
    this.cashierName,
    required this.totalRevenue,
    required this.transactionCount,
    required this.cashCount,
    required this.qrisCount,
    required this.totalExpenses,
  });
}

class ShiftReportRepository {
  /// Compute summary untuk 1 shift (always dynamic, no caching — spec D10).
  Future<ShiftSummary> computeSummary(Shift shift) async {
    final businessId = BusinessContext.instance.activeBusinessId;
    if (businessId == null) throw StateError('No active business');

    // Query transactions (exclude soft-deleted)
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.shiftId.equals(shift.id) &
              t.businessId.equals(businessId) &
              t.deletedAt.isNull()))
        .get();

    // Query expenses (exclude soft-deleted)
    final exps = await (db.select(db.expenses)
          ..where((e) =>
              e.shiftId.equals(shift.id) &
              e.businessId.equals(businessId) &
              e.deletedAt.isNull()))
        .get();

    // Get cashier name
    final user = await (db.select(db.users)
          ..where((u) => u.id.equals(shift.userId))
          ..limit(1))
        .getSingleOrNull();

    return ShiftSummary(
      shift: shift,
      cashierName: user?.username,
      totalRevenue: txs.fold(0, (sum, t) => sum + t.total),
      transactionCount: txs.length,
      cashCount: txs.where((t) => t.paymentMethod == 'cash').length,
      qrisCount: txs.where((t) => t.paymentMethod == 'qris').length,
      totalExpenses: exps.fold(0, (sum, e) => sum + e.amount),
    );
  }

  /// Query shifts dalam periode tertentu, compute summary untuk masing-masing.
  Future<List<ShiftSummary>> getShiftsForPeriod(
      DateTime start, DateTime end) async {
    final businessId = BusinessContext.instance.activeBusinessId;
    if (businessId == null) return [];

    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);

    final shifts = await (db.select(db.shifts)
          ..where((s) =>
              s.businessId.equals(businessId) &
              s.deletedAt.isNull() &
              s.startAt.isBetweenValues(start, endOfDay))
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();

    return Future.wait(shifts.map(computeSummary));
  }

  /// Total revenue untuk semua shifts dalam periode.
  Future<({int totalRevenue, int totalShifts, int totalTransactions})>
      getPeriodTotals(DateTime start, DateTime end) async {
    final summaries = await getShiftsForPeriod(start, end);
    return (
      totalRevenue: summaries.fold(0, (s, x) => s + x.totalRevenue),
      totalShifts: summaries.length,
      totalTransactions: summaries.fold(0, (s, x) => s + x.transactionCount),
    );
  }
}
