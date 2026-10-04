import '../../../data/app_database.dart';
import '../../../shared/auth/pin_owner.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/periode/periode.dart';

/// Satu-satunya pintu akses data pengeluaran.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
///
/// Pengeluaran kasir terikat shift yang sedang berjalan. Owner tidak punya
/// shift: pengeluarannya tanpa shift dan hanya dikelompokkan per tanggal
/// (v33). Rekapnya dibaca lewat [watchPengeluaranPeriode] (halaman
/// Pengeluaran) dan [getAllExpensesForOwner] (Laporan).
class ExpenseRepository {
  final AppDatabase _db;

  ExpenseRepository(this._db);

  // ---- TULIS ----

  /// Catat pengeluaran baru.
  ///
  /// Kasir: wajib pada shift yang sedang berjalan ([shiftId]). Owner: tanpa
  /// shift ([shiftId] null) — pengeluarannya hanya dikelompokkan per tanggal
  /// (keputusan owner 2026-10-04). Aturan ini ditegakkan DI SINI, bukan
  /// hanya lewat tombol di halaman.
  Future<void> addExpense({
    required String? shiftId,
    required String userId,
    required String description,
    required int amount,
    String category = 'bahan_baku',
    int qty = 1,
  }) {
    if (shiftId == null && !SessionManager.instance.isOwner) {
      throw StateError('Pengeluaran kasir harus dicatat saat shift berjalan.');
    }
    return _db.addExpense(
      shiftId: shiftId,
      userId: userId,
      description: description,
      amount: amount,
      category: category,
      qty: qty,
    );
  }

  // ---- PEMBATALAN ----
  //
  // Pengeluaran tidak bisa diedit dan tidak pernah dihapus — yang salah
  // DIBATALKAN (dengan siapa, kapan, alasannya) lalu dicatat ulang. Dulu
  // kasir bisa menghapus atau mengubah jumlahnya tanpa jejak. Aturannya sama
  // dengan pembatalan transaksi.

  /// Kasir wajib memasukkan PIN owner; owner yang sedang login tidak.
  bool get perluPinOwner => !SessionManager.instance.isOwner;

  /// Owner: pengeluaran apa pun yang belum batal. Kasir: hanya miliknya di
  /// shift yang SEDANG berjalan.
  bool bolehDibatalkan(Expense e) {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null || e.deletedAt != null) return false;
    if (sesi.isOwner) return true;
    return sesi.shiftId != null &&
        e.shiftId == sesi.shiftId &&
        e.userId == sesi.userId;
  }

  /// Batalkan [e]. Aturannya ditegakkan DI SINI, bukan hanya dengan
  /// menyembunyikan tombol di halaman.
  Future<void> batalkanPengeluaran(
    Expense e, {
    required String alasan,
    String? pinOwner,
  }) async {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) throw StateError('Belum masuk.');
    final teks = alasan.trim();
    if (teks.isEmpty) throw ArgumentError('Alasan wajib diisi.');
    if (!bolehDibatalkan(e)) {
      throw StateError(e.deletedAt != null
          ? 'Pengeluaran ini sudah dibatalkan.'
          : 'Pengeluaran ini hanya bisa dibatalkan owner.');
    }
    if (perluPinOwner) await PemeriksaPinOwner(_db).periksa(pinOwner ?? '');

    await _db.batalkanPengeluaran(e.id, olehUserId: sesi.userId, alasan: teks);
  }

  // ---- BACA ----

  /// Nama akun per id — untuk menampilkan siapa yang membatalkan.
  Future<Map<String, String>> namaAkun() => _db.namaAkun();

  /// Pengeluaran satu shift, terbaru dulu — TERMASUK yang dibatalkan, karena
  /// halaman Pengeluaran menampilkannya dengan label dan tidak menghitungnya.
  Stream<List<Expense>> watchExpensesByShift(String shiftId) =>
      _db.watchExpensesByShift(shiftId, termasukBatal: true);

  /// Pengeluaran sekumpulan shift sekaligus, dikelompokkan per shift —
  /// TERMASUK yang dibatalkan (lihat [watchExpensesByShift]). Shift tanpa
  /// pengeluaran tidak muncul sebagai kunci — itulah yang dipakai halaman
  /// Pengeluaran untuk membuang shift kosong dari riwayat.
  Future<Map<String, List<Expense>>> getExpensesForShifts(
    List<String> shiftIds,
  ) =>
      _db.getExpensesForShifts(shiftIds, termasukBatal: true);

  /// Pengeluaran satu periode untuk halaman Pengeluaran owner — TERMASUK
  /// yang dibatalkan. Berbunyi lagi tiap ada perubahan, termasuk dari sinkron.
  Stream<List<Expense>> watchPengeluaranPeriode(Periode p) =>
      _db.watchExpensesInRange(p.dari, p.batasAkhir);

  /// Rekap pengeluaran seluruh kasir beserta nama pencatatnya.
  /// Dipakai owner di halaman Laporan; rentang tanggal opsional.
  Future<List<ExpenseEntry>> getAllExpensesForOwner({
    DateTime? startDate,
    DateTime? endDate,
  }) =>
      _db.getAllExpensesForOwner(startDate: startDate, endDate: endDate);
}
