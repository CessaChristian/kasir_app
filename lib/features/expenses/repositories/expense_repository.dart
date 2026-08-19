import '../../../data/app_database.dart';

/// Satu-satunya pintu akses data pengeluaran.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
///
/// Pengeluaran selalu terikat shift: kolom `shift_id` wajib diisi, sehingga
/// hanya kasir yang sedang menjalankan shift bisa mencatatnya. Owner tidak
/// punya shift, jadi ia hanya membaca rekapnya lewat [getAllExpensesForOwner].
class ExpenseRepository {
  final AppDatabase _db;

  ExpenseRepository(this._db);

  // ---- TULIS ----

  /// Catat pengeluaran baru pada shift yang sedang berjalan.
  Future<void> addExpense({
    required String shiftId,
    required String userId,
    required String description,
    required int amount,
  }) =>
      _db.addExpense(
        shiftId: shiftId,
        userId: userId,
        description: description,
        amount: amount,
      );

  /// Ubah nominal dan keterangan pengeluaran.
  /// Pemeriksaan izin dilakukan pemanggil sebelum method ini dijalankan.
  Future<void> updateExpense({
    required String id,
    required int amount,
    required String description,
  }) =>
      _db.updateExpense(id: id, amount: amount, description: description);

  /// Tandai pengeluaran terhapus — barisnya tetap ada supaya penghapusannya
  /// bisa ikut tersinkron ke database pusat nanti.
  Future<void> deleteExpense(String id) => _db.deleteExpense(id);

  // ---- BACA ----

  /// Pengeluaran satu shift, terbaru dulu. Yang terhapus tidak ikut.
  Stream<List<Expense>> watchExpensesByShift(String shiftId) =>
      _db.watchExpensesByShift(shiftId);

  /// Versi sekali-ambil dari [watchExpensesByShift] — dipakai kartu riwayat
  /// shift yang hanya perlu memuat sekali saat dibuka.
  Future<List<Expense>> getExpensesByShift(String shiftId) =>
      _db.getExpensesByShift(shiftId);

  /// Rekap pengeluaran seluruh kasir beserta nama pencatatnya.
  /// Dipakai owner di halaman Laporan; rentang tanggal opsional.
  Future<List<ExpenseEntry>> getAllExpensesForOwner({
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      _db.getAllExpensesForOwner(startDate: startDate, endDate: endDate);
}
