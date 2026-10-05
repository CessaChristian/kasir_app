import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/periode/periode.dart';
import '../models/ringkasan_shift.dart';

/// Satu-satunya pintu akses data shift untuk keperluan operasional:
/// kartu shift aktif di dashboard, riwayat shift, dan ringkasan tutup shift.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
class ShiftRepository {
  final AppDatabase _db;

  ShiftRepository(this._db);

  /// Riwayat shift seorang kasir pada business aktif, terbaru dulu.
  /// Shift beserta nama kasirnya. [userId] null = semua kasir (untuk owner).
  Future<List<ShiftEntry>> getShiftsWithUser({String? userId}) =>
      _db.getShiftsWithUser(userId: userId);

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

  /// Shift yang DIMULAI dalam [periode], terbaru dulu, beserta transaksi dan
  /// pengeluarannya (termasuk yang dibatalkan). [hanyaUserId] diisi untuk
  /// akun yang hanya boleh melihat shift miliknya sendiri.
  ///
  /// Ikut berubah sesudah refresh menarik transaksi baru dari server.
  Stream<List<RingkasanShift>> watchRiwayatShift(
    Periode periode, {
    String? hanyaUserId,
  }) => _pantau(
        () => _ringkas((s) {
          var syarat = s.deletedAt.isNull() &
              s.startAt.isBiggerOrEqualValue(periode.dari) &
              s.startAt.isSmallerThanValue(periode.batasAkhir);
          if (hanyaUserId != null) {
            syarat = syarat & s.userId.equals(hanyaUserId);
          }
          return syarat;
        }),
      );

  /// Satu shift untuk Detail Shift; null kalau tidak ada.
  Stream<RingkasanShift?> watchShift(String shiftId) => _pantau(
        () async =>
            (await _ringkas((s) => s.id.equals(shiftId))).firstOrNull,
      );

  /// Muat ulang setiap kali shift, transaksi, pengeluaran, atau nama akun
  /// berubah.
  ///
  /// Kueri pantau drift, bukan `async*` + `await for` pada `tableUpdates`:
  /// generator seperti itu tidak selesai saat pendengarnya berhenti (halaman
  /// ditutup), jadi pembatalannya menggantung.
  Stream<T> _pantau<T>(Future<T> Function() muat) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {_db.shifts, _db.transactions, _db.expenses, _db.users},
      )
      .watch()
      .asyncMap((_) => muat());

  Future<List<RingkasanShift>> _ringkas(
    Expression<bool> Function($ShiftsTable s) syarat,
  ) async {
    final shifts = await (_db.select(_db.shifts)
          ..where(syarat)
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();
    if (shifts.isEmpty) return const [];

    final id = shifts.map((s) => s.id).toList();
    final transaksi = await (_db.select(_db.transactions)
          ..where((t) => t.shiftId.isIn(id))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final pengeluaran = await (_db.select(_db.expenses)
          ..where((e) => e.shiftId.isIn(id))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    final nama = await _db.namaAkun();

    return [
      for (final s in shifts)
        RingkasanShift(
          shift: s,
          namaKasir: nama[s.userId],
          transaksi: transaksi.where((t) => t.shiftId == s.id).toList(),
          pengeluaran: pengeluaran.where((e) => e.shiftId == s.id).toList(),
        ),
    ];
  }

  /// Nama akun per id — untuk "Dibatalkan · nama, jam".
  Future<Map<String, String>> namaAkun() => _db.namaAkun();

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
