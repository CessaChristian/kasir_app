import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/periode/periode.dart';
import '../models/ringkasan_laporan.dart';

/// Data halaman Laporan (dan angka hari ini di Dashboard owner).
class LaporanRepository {
  final AppDatabase _db;

  LaporanRepository(this._db);

  /// Ikut berubah setiap kali transaksi, pengeluaran, shift, produk, atau
  /// kategori berubah — mis. sesudah refresh menarik data baru dari server.
  ///
  /// Tanpa izin: aliran berisi galat, bukan lemparan saat dipanggil —
  /// halamannya dibangun ulang dengan aliran baru, dan lemparan di tengah
  /// build membuat halamannya rusak (review D1).
  Stream<RingkasanLaporan> watchLaporan(Periode periode) {
    try {
      SessionManager.instance.requirePermission('view_report');
    } catch (e) {
      return Stream.error(e);
    }
    return _db
        .pemicuTabel({
          _db.transactions,
          _db.transactionItems,
          _db.expenses,
          _db.shifts,
          _db.products,
          _db.categories,
        })
        .asyncMap((_) => muat(periode));
  }

  /// Owner dan pemegang `view_report` saja — dulu cuma halamannya yang
  /// memeriksa.
  ///
  /// [ringkas]: hanya angka total (pendapatan, transaksi, pengeluaran, tunai
  /// & QRIS) — item, produk, dan kategori tidak dibaca, jadi rincian per
  /// produk/kategori kosong. Dihitung fungsi yang SAMA, jadi angkanya tetap
  /// sama dengan Laporan. Untuk Dashboard owner, yang memuat ulang tiap
  /// menit dan tiap ada perubahan (review E2).
  Future<RingkasanLaporan> muat(
    Periode periode, {
    DateTime? sekarang,
    bool ringkas = false,
  }) async {
    SessionManager.instance.requirePermission('view_report');
    final dari = periode.dari;
    final sampai = periode.batasAkhir;

    final transaksi =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.createdAt.isBiggerOrEqualValue(dari) &
                    t.createdAt.isSmallerThanValue(sampai),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    // Item diambil lewat subkueri, bukan `isIn(daftar id)` dari Dart: SQLite
    // menolak lebih dari ±32.766 isian per kueri, jadi periode dengan
    // transaksi sebanyak itu (±1 tahun di 100 transaksi/hari) membuat halaman
    // Laporan gagal dimuat selamanya. JOIN biasa juga tidak dipakai: tanpa
    // indeks di transaction_items.transaction_id, SQLite mencocokkan setiap
    // pasangan baris (40.000 transaksi = 70 detik).
    final tx = _db.transactions;
    final idSah = _db.selectOnly(tx)
      ..addColumns([tx.id])
      ..where(
        tx.createdAt.isBiggerOrEqualValue(dari) &
            tx.createdAt.isSmallerThanValue(sampai) &
            tx.deletedAt.isNull(),
      );
    final item = ringkas
        ? const <TransactionItem>[]
        : await (_db.select(_db.transactionItems)..where(
                (i) =>
                    i.transactionId.isInQuery(idSah) & i.deletedAt.isNull(),
              ))
              .get();
    final itemPerTransaksi = <String, List<TransactionItem>>{};
    for (final i in item) {
      itemPerTransaksi.putIfAbsent(i.transactionId, () => []).add(i);
    }

    final pengeluaran =
        await (_db.select(_db.expenses)
              ..where(
                (e) =>
                    e.createdAt.isBiggerOrEqualValue(dari) &
                    e.createdAt.isSmallerThanValue(sampai),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
            .get();
    final shift =
        await (_db.select(_db.shifts)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.startAt.isBiggerOrEqualValue(dari) &
                  s.startAt.isSmallerThanValue(sampai),
            ))
            .get();

    return ringkasLaporan(
      periode: periode,
      transaksi: transaksi,
      item: itemPerTransaksi,
      pengeluaran: pengeluaran,
      shift: shift,
      produk: ringkas ? const [] : await _db.select(_db.products).get(),
      kategori: ringkas ? const [] : await _db.select(_db.categories).get(),
      sekarang: sekarang ?? DateTime.now(),
    );
  }

  /// Nama akun per id — untuk "oleh siapa" di daftar yang dibatalkan.
  Future<Map<String, String>> namaAkun() => _db.namaAkun();

  /// [namaAkun] yang ikut berubah saat sinkron membawa akun/nama baru.
  Stream<Map<String, String>> watchNamaAkun() => _db.watchNamaAkun();
}
