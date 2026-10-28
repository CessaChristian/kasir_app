import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../data/uuid_helper.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/periode/periode.dart';
import '../models/produk_laris.dart';
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
  }) {
    // Shift orang lain hanya untuk owner dan pemegang `view_all_shifts` —
    // dulu cuma halamannya yang memeriksa.
    final sesi = SessionManager.instance;
    if (hanyaUserId == null || hanyaUserId != sesi.currentUserId) {
      sesi.requirePermission('view_all_shifts');
    }
    return _pantau(
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
  }

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
          namaKasir: s.namaKasir(nama),
          transaksi: transaksi.where((t) => t.shiftId == s.id).toList(),
          pengeluaran: pengeluaran.where((e) => e.shiftId == s.id).toList(),
        ),
    ];
  }

  /// Shift terbaru [userId] yang sudah ditutup, untuk "Shift selesai" di
  /// dashboard kasir; null kalau belum pernah ada.
  Stream<RingkasanShift?> watchShiftTerakhirSelesai(String userId) => _pantau(
        () async {
          final terakhir = await (_db.select(_db.shifts)
                ..where((s) =>
                    s.userId.equals(userId) &
                    s.endAt.isNotNull() &
                    s.deletedAt.isNull())
                ..orderBy([(s) => OrderingTerm.desc(s.endAt)])
                ..limit(1))
              .getSingleOrNull();
          if (terakhir == null) return null;
          return (await _ringkas((s) => s.id.equals(terakhir.id))).firstOrNull;
        },
      );

  /// Buka shift untuk [userId] dengan uang [kasAwal] di laci. Kalau [userId]
  /// ternyata masih punya shift terbuka (dibuka di HP lain), shift itu yang
  /// dikembalikan — tidak lahir shift kedua.
  ///
  /// Pemanggil sebaiknya menarik shift dari server lebih dulu
  /// (`AuthRepository.cariShiftTerbuka`).
  Future<String> bukaShift({required String userId, required int kasAwal}) async {
    SessionManager.instance.requirePermission('open_close_shift');
    if (kasAwal < 0) throw ArgumentError('Kas awal tidak boleh negatif');
    return _db.transaction(() async {
      final terbuka = await (_db.select(_db.shifts)
            ..where((s) =>
                s.userId.equals(userId) &
                s.endAt.isNull() &
                s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.asc(s.startAt)])
            ..limit(1))
          .getSingleOrNull();
      if (terbuka != null) return terbuka.id;

      final id = newUuid();
      await _db.into(_db.shifts).insert(
            ShiftsCompanion.insert(
              id: Value(id),
              userId: userId,
              userName: Value(await _db.usernameAkun(userId)),
              kasAwal: Value(kasAwal),
            ),
          );
      return id;
    });
  }

  /// Tutup shift: catat jam selesainya dan kirim ke HP lain. Pemeriksaan
  /// "masih dipegang HP lain" dilakukan pemanggil (butuh server).
  Future<void> tutupShift(String shiftId) async {
    SessionManager.instance.requirePermission('open_close_shift');
    final sekarang = DateTime.now();
    await (_db.update(_db.shifts)
          ..where((s) => s.id.equals(shiftId) & s.endAt.isNull()))
        .write(
      ShiftsCompanion(
        endAt: Value(sekarang),
        updatedAt: Value(sekarang),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// "Produk Paling Laris" minggu [awal] (Senin 00.00, lihat [awalMinggu])
  /// dari SEMUA kasir — produk toko yang paling banyak terjual. Transaksi
  /// yang dibatalkan tidak dihitung; produk yang sudah dihapus tidak
  /// ditampilkan karena tidak bisa dijual lagi.
  Stream<List<ProdukLaris>> watchProdukLarisMinggu(
    DateTime awal, {
    int batas = 4,
  }) => _laris(
        't.created_at >= ?',
        [Variable.withDateTime(awal)],
        batas: batas,
        hanyaYangAda: true,
      );

  /// Yang paling banyak terjual di satu shift ("Terlaris di Shift
  /// Terakhir"). Produk yang sudah dihapus tetap ikut, dengan nama di struk.
  Stream<List<ProdukLaris>> watchTerlarisShift(
    String shiftId, {
    int batas = 4,
  }) => _laris('t.shift_id = ?', [Variable.withString(shiftId)], batas: batas);

  Stream<List<ProdukLaris>> _laris(
    String syarat,
    List<Variable> nilai, {
    required int batas,
    bool hanyaYangAda = false,
  }) => _db
      .customSelect(
        'SELECT ti.product_id AS id, MAX(ti.product_name) AS nama, '
        'SUM(ti.qty) AS jumlah '
        'FROM transaction_items ti '
        'JOIN transactions t ON t.id = ti.transaction_id '
        'WHERE t.deleted_at IS NULL AND ti.deleted_at IS NULL AND $syarat '
        'GROUP BY ti.product_id',
        variables: nilai,
        readsFrom: {_db.transactions, _db.transactionItems, _db.products},
      )
      .watch()
      .asyncMap((baris) async {
        final id = [for (final b in baris) b.read<String>('id')];
        final produk = {
          for (final p in await (_db.select(_db.products)
                ..where((p) => p.id.isIn(id) & p.deletedAt.isNull()))
              .get())
            p.id: p,
        };
        final hasil = [
          for (final b in baris)
            if (!hanyaYangAda || produk.containsKey(b.read<String>('id')))
              ProdukLaris(
                idProduk: b.read<String>('id'),
                nama: produk[b.read<String>('id')]?.name ??
                    b.read<String>('nama'),
                terjual: b.read<int>('jumlah'),
                produk: produk[b.read<String>('id')],
              ),
        ]..sort((a, b) {
            final beda = b.terjual.compareTo(a.terjual);
            return beda != 0
                ? beda
                : a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
          });
        return hasil.take(batas).toList();
      });

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
