import 'package:drift/drift.dart';

import '../../../data/app_database.dart';

/// Satu-satunya pintu akses data shift untuk keperluan operasional:
/// kartu shift aktif di dashboard, riwayat shift, dan ringkasan tutup shift.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
///
/// Berbeda dari `ShiftReportRepository` di `features/reports/` yang menghitung
/// ringkasan shift untuk halaman Pantau Shift milik owner. Yang ini melayani
/// shift milik kasir yang sedang login.
class ShiftRepository {
  final AppDatabase _db;

  ShiftRepository(this._db);

  /// Riwayat shift seorang kasir pada business aktif, terbaru dulu.
  Future<List<Shift>> getShiftsByUser(String userId) =>
      _db.getShiftsByUser(userId);

  /// Ambil satu shift berdasarkan id. Null kalau tidak ada.
  Future<Shift?> getById(String shiftId) =>
      (_db.select(_db.shifts)..where((s) => s.id.equals(shiftId)))
          .getSingleOrNull();

  /// Transaksi milik satu shift. Yang sudah dihapus tidak ikut.
  Future<List<Transaction>> getTransactionsForShift(String shiftId) =>
      (_db.select(_db.transactions)
            ..where((t) => t.shiftId.equals(shiftId) & t.deletedAt.isNull()))
          .get();

  /// Total pendapatan satu shift — dipakai dialog tutup shift.
  ///
  /// Filter `deletedAt` WAJIB. Sebelum dipindah ke sini, query ini ditulis
  /// langsung di dashboard_page tanpa filter tersebut, sehingga transaksi
  /// yang sudah dihapus kasir tetap terhitung sebagai pendapatan shift.
  Future<int> getShiftRevenue(String shiftId) async {
    final transactions = await getTransactionsForShift(shiftId);
    return transactions.fold<int>(0, (sum, tx) => sum + tx.total);
  }
}
