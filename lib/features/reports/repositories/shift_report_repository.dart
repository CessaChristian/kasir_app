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
  ///
  /// [onlyUserId] — jika di-set, hanya shift milik user tsb yang diambil
  /// (dipakai untuk user tanpa permission `view_all_shifts` yang hanya boleh
  /// melihat shift sendiri). Null = semua shift di business aktif.
  Future<List<ShiftSummary>> getShiftsForPeriod(
      DateTime start, DateTime end, {String? onlyUserId}) async {
    final businessId = BusinessContext.instance.activeBusinessId;
    if (businessId == null) return [];

    final startOfDay = DateTime(start.year, start.month, start.day);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);

    final shifts = await (db.select(db.shifts)
          ..where((s) {
            var cond = s.businessId.equals(businessId) &
                s.deletedAt.isNull() &
                s.startAt.isBetweenValues(startOfDay, endOfDay);
            if (onlyUserId != null) {
              cond = cond & s.userId.equals(onlyUserId);
            }
            return cond;
          })
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();

    return Future.wait(shifts.map(computeSummary));
  }

  /// Semua transaksi (belum dihapus) pada sebuah shift, terurut waktu naik.
  /// Dipakai halaman detail shift untuk menampilkan daftar transaksi.
  Future<List<Transaction>> getTransactionsForShift(String shiftId) async {
    final businessId = BusinessContext.instance.activeBusinessId;
    if (businessId == null) return [];
    return (db.select(db.transactions)
          ..where((t) =>
              t.shiftId.equals(shiftId) &
              t.businessId.equals(businessId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
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
