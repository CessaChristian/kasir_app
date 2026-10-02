import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';
import '../../../data/perangkat/kode_nota.dart';
import '../../../shared/auth/cakupan_riwayat.dart';
import '../../../shared/auth/pin_owner.dart';
import '../../../shared/auth/session_manager.dart';

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

  // ---- PEMBATALAN ----
  //
  // Transaksi tidak pernah dihapus, hanya DIBATALKAN — dengan siapa, kapan,
  // dan alasannya — lalu disimpan selamanya sebagai bukti untuk owner.
  // Dulu tombolnya "Hapus": kasir bisa menghilangkan transaksinya kapan saja
  // tanpa jejak.

  /// Kasir wajib memasukkan PIN owner; owner yang sedang login tidak.
  bool get perluPinOwner => !SessionManager.instance.isOwner;

  /// Owner: transaksi apa pun yang belum batal. Kasir: hanya miliknya sendiri
  /// di shift yang SEDANG berjalan — shift yang sudah ditutup dan diserahkan
  /// ke owner tidak boleh berubah diam-diam.
  bool bolehDibatalkan(Transaction tx) {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null || tx.deletedAt != null) return false;
    if (sesi.isOwner) return true;
    return sesi.shiftId != null &&
        tx.shiftId == sesi.shiftId &&
        tx.cashierUserId == sesi.userId;
  }

  /// Batalkan [tx]. Aturannya ditegakkan DI SINI, bukan hanya dengan
  /// menyembunyikan tombol di halaman. PIN owner diperiksa
  /// [PemeriksaPinOwner] — sama dengan pembatalan pengeluaran.
  Future<void> batalkanTransaksi(
    Transaction tx, {
    required String alasan,
    String? pinOwner,
  }) async {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) throw StateError('Belum masuk.');
    final teks = alasan.trim();
    if (teks.isEmpty) throw ArgumentError('Alasan wajib diisi.');
    if (!bolehDibatalkan(tx)) {
      throw StateError(tx.deletedAt != null
          ? 'Transaksi ini sudah dibatalkan.'
          : 'Transaksi ini hanya bisa dibatalkan owner.');
    }
    if (perluPinOwner) await PemeriksaPinOwner(_db).periksa(pinOwner ?? '');

    await _db.batalkanTransaksi(tx.id, olehUserId: sesi.userId, alasan: teks);
  }

  /// Nama akun per id — untuk menampilkan siapa yang membatalkan.
  Future<Map<String, String>> namaAkun() => _db.namaAkun();

  // ---- BACA ----

  /// Semua transaksi business aktif, terbaru dulu. Yang terhapus tidak ikut.
  Stream<List<Transaction>> watchTransactions() => _db.watchTransactions();

  /// Transaksi untuk halaman Riwayat, dibatasi [cakupan] akun yang melihat.
  ///
  /// Transaksi yang DIBATALKAN ikut tampil — halaman Riwayat memberinya label
  /// dan tidak menghitungnya di total.
  Stream<List<Transaction>> watchRiwayat(CakupanRiwayat cakupan) =>
      switch (cakupan.jenis) {
        JenisCakupan.semua => _db.watchTransactions(termasukBatal: true),
        JenisCakupan.milikSendiri => _db.watchTransactions(
            kasirId: cakupan.userId, termasukBatal: true),
        JenisCakupan.shiftAktif => cakupan.shiftId == null
            ? Stream.value(const <Transaction>[])
            : _db.watchTransactions(
                shiftId: cakupan.shiftId, termasukBatal: true),
      };

  /// Item milik satu transaksi — dipakai layar detail struk. [termasukBatal]
  /// untuk struk yang dibatalkan, yang isinya tetap perlu terlihat.
  Future<List<TransactionItem>> getTransactionItems(
    String transactionId, {
    bool termasukBatal = false,
  }) =>
      _db.getTransactionItems(transactionId, termasukBatal: termasukBatal);

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
