import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/perangkat/kode_nota.dart';

/// Satu-satunya pintu akses data transaksi penjualan.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
///
/// Dipakai lintas fitur — Kasir, Riwayat, Dashboard, dan Laporan semuanya
/// membaca transaksi. Repository dikelompokkan per DOMAIN DATA, bukan per
/// halaman, jadi satu repository melayani banyak layar.
class SalesRepository {
  final AppDatabase _db;

  SalesRepository(this._db);

  // ---- TULIS ----

  /// Catat satu penjualan beserta itemnya.
  ///
  /// Seluruhnya dalam satu transaction database: kalau salah satu produk
  /// ternyata sudah dihapus, tidak ada satu pun baris yang tertulis.
  ///
  /// [transactionId] wajib UUID (kunci internal, tidak pernah tampil).
  /// Nomor nota dibuat sendiri oleh database dan dikembalikan method ini.
  Future<String> createSale({
    required String transactionId,
    required List<SaleLine> lines,
    required String paymentMethod,
    required String orderType,
    int? cashReceived,
    String? cashierUserId,
    String? shiftId,
  }) async {
    // Penanda perangkat diambil di sini, bukan di halaman: halaman tidak
    // perlu tahu nomor nota dibentuk dari apa, dan database tetap menerima
    // nilai jadi sehingga bisa diuji tanpa brankas.
    final kode = await KodeNota.ambil();
    return _db.createSale(
      transactionId: transactionId,
      lines: lines,
      paymentMethod: paymentMethod,
      orderType: orderType,
      cashReceived: cashReceived,
      cashierUserId: cashierUserId,
      shiftId: shiftId,
      kodePerangkat: kode,
    );
  }

  /// Tandai transaksi terhapus. Item transaksinya ikut ditandai terhapus
  /// dalam satu transaction.
  Future<void> softDeleteTransaction(String transactionId) =>
      _db.softDeleteTransaction(transactionId);

  // ---- BACA ----

  /// Semua transaksi business aktif, terbaru dulu. Yang terhapus tidak ikut.
  Stream<List<Transaction>> watchTransactions() => _db.watchTransactions();

  /// Item milik satu transaksi — dipakai layar detail struk.
  Future<List<TransactionItem>> getTransactionItems(String transactionId) =>
      _db.getTransactionItems(transactionId);

  /// Item untuk banyak transaksi sekaligus, dikelompokkan per `transactionId`.
  ///
  /// Dipakai ekspor laporan supaya tidak melakukan satu query per transaksi.
  Future<Map<String, List<TransactionItem>>> getTransactionItemsForIds(
    List<String> transactionIds,
  ) =>
      _db.getTransactionItemsForIds(transactionIds);

  /// Transaksi dalam rentang tanggal — dipakai dashboard dan laporan.
  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) =>
      _db.getTransactionsByDateRange(startDate, endDate);
}
