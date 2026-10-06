import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/periode/periode.dart';
import '../models/ringkasan_laporan.dart';

/// Data halaman Laporan (dan angka hari ini di Dashboard owner).
class LaporanRepository {
  final AppDatabase _db;

  LaporanRepository(this._db);

  /// Ikut berubah setiap kali transaksi, pengeluaran, shift, produk, atau
  /// kategori berubah — mis. sesudah refresh menarik data baru dari server.
  Stream<RingkasanLaporan> watchLaporan(Periode periode) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.transactions,
          _db.transactionItems,
          _db.expenses,
          _db.shifts,
          _db.products,
          _db.categories,
        },
      )
      .watch()
      .asyncMap((_) => muat(periode));

  Future<RingkasanLaporan> muat(Periode periode, {DateTime? sekarang}) async {
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
    final idSah = [
      for (final t in transaksi)
        if (t.deletedAt == null) t.id,
    ];
    final item = idSah.isEmpty
        ? const <TransactionItem>[]
        : await (_db.select(_db.transactionItems)..where(
                (i) => i.transactionId.isIn(idSah) & i.deletedAt.isNull(),
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
      produk: await _db.select(_db.products).get(),
      kategori: await _db.select(_db.categories).get(),
      sekarang: sekarang ?? DateTime.now(),
    );
  }

  /// Nama akun per id — untuk "oleh siapa" di daftar yang dibatalkan.
  Future<Map<String, String>> namaAkun() => _db.namaAkun();
}
