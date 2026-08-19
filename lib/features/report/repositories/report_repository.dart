import '../../../data/app_database.dart';
import '../../../data/models/top_product.dart';

/// Satu-satunya pintu akses data laporan dan rekap penjualan.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
///
/// Semua method di sini bersifat BACA dan sudah teragregasi — perhitungannya
/// dilakukan di lapisan database, bukan di widget.
class ReportRepository {
  final AppDatabase _db;

  ReportRepository(this._db);

  /// Rekap satu hari: pemasukan, pengeluaran, laba, rincian metode bayar.
  Future<ReportSummary> getReportSummary(DateTime date) =>
      _db.getReportSummary(date);

  /// Rekap satu hari dipecah per kasir.
  Future<List<EmployeeReportSummary>> getEmployeeReportSummary(DateTime date) =>
      _db.getEmployeeReportSummary(date);

  /// Rekap satu bulan penuh.
  Future<ReportSummary> getMonthlyReportSummary(int year, int month) =>
      _db.getMonthlyReportSummary(year, month);

  /// Pendapatan harian sepanjang satu bulan — untuk grafik tren.
  Future<List<DailyTrend>> getDailyTrends(int year, int month) =>
      _db.getDailyTrends(year, month);

  /// Rekap per kasir untuk rentang tanggal bebas.
  Future<List<EmployeeReportSummary>> getEmployeeReportSummaryForRange(
    DateTime startDate,
    DateTime endDate,
  ) =>
      _db.getEmployeeReportSummaryForRange(startDate, endDate);

  /// Produk terlaris dalam rentang tanggal.
  ///
  /// Ada di sini, bukan di `ProductRepository`, karena sumbernya
  /// `transaction_items` dalam rentang waktu — pertanyaan laporan, bukan
  /// pertanyaan katalog produk.
  Future<List<TopProduct>> getTopSellingProducts(
    DateTime startDate,
    DateTime endDate, {
    int limit = 5,
  }) =>
      _db.getTopSellingProducts(startDate, endDate, limit: limit);
}
