import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../report/repositories/laporan_repository.dart';

/// Shift kasir yang sedang berjalan, untuk baris status di dashboard owner.
class ShiftBerjalan {
  final String namaKasir;
  final DateTime mulai;
  final int transaksi;
  final int pendapatan;

  const ShiftBerjalan({
    required this.namaKasir,
    required this.mulai,
    required this.transaksi,
    required this.pendapatan,
  });
}

/// Isi kartu "Ringkasan hari ini" di dashboard owner.
class RingkasanOwner {
  final int pendapatan;
  final int transaksi;
  final int pengeluaran;
  final int tunai;
  final int qris;

  /// Pendapatan kemarin dari jam 00.00 sampai jam yang sama dengan sekarang.
  final int pendapatanKemarin;

  final List<ShiftBerjalan> shiftBerjalan;
  final DateTime? shiftTerakhirDitutup;

  const RingkasanOwner({
    required this.pendapatan,
    required this.transaksi,
    required this.pengeluaran,
    required this.tunai,
    required this.qris,
    required this.pendapatanKemarin,
    required this.shiftBerjalan,
    required this.shiftTerakhirDitutup,
  });

  int get labaKotor => pendapatan - pengeluaran;

  int? get persenVsKemarin => persenPerubahan(pendapatan, pendapatanKemarin);
}

/// Persen naik/turun dari [kemarin] ke [sekarang], dibulatkan.
///
/// Null kalau kemarin nol — "naik tak terhingga persen" tidak berarti apa-apa,
/// jadi lencananya disembunyikan. (Prototipe desain mengakalinya dengan
/// membagi 1, yang menghasilkan angka seperti "+125000000%".)
int? persenPerubahan(int sekarang, int kemarin) {
  if (kemarin <= 0) return null;
  return ((sekarang - kemarin) * 100 / kemarin).round();
}

/// Satu-satunya pintu data dashboard owner.
///
/// Transaksi dan pengeluaran yang DIBATALKAN tidak dihitung — semua kueri di
/// bawah menyaring `deleted_at`.
class DasborOwnerRepository {
  final AppDatabase _db;

  DasborOwnerRepository(this._db);

  /// Berbunyi setiap kali transaksi, pengeluaran, atau shift berubah —
  /// termasuk yang datang dari sinkron — supaya dashboard memuat ulang sendiri.
  Stream<void> perubahan() => _db
      .tableUpdates(TableUpdateQuery.onAllTables(
          [_db.transactions, _db.expenses, _db.shifts]))
      .map((_) {});

  Future<RingkasanOwner> muat({DateTime? sekarang}) async {
    final now = sekarang ?? DateTime.now();
    final awalHari = DateTime(now.year, now.month, now.day);
    final awalKemarin = DateTime(now.year, now.month, now.day - 1);
    final batasKemarin = DateTime(now.year, now.month, now.day - 1, now.hour,
        now.minute, now.second);

    // Hitungan yang sama dengan Laporan, supaya angka keduanya pasti sama.
    // Hanya angka totalnya: dulu seluruh laporan (item, produk, kategori,
    // grafik) dihitung tiap menit lalu dibuang (review E2).
    final hariIni = await LaporanRepository(
      _db,
    ).muat(Periode.hari(now), sekarang: now, ringkas: true);
    final kemarin =
        await _db.getTransactionsByDateRange(awalKemarin, batasKemarin);

    return RingkasanOwner(
      pendapatan: hariIni.pendapatan,
      transaksi: hariIni.jumlahTransaksi,
      pengeluaran: hariIni.pengeluaran,
      tunai: hariIni.tunai.jumlah,
      qris: hariIni.qris.jumlah,
      pendapatanKemarin: kemarin.fold(0, (s, t) => s + t.total),
      shiftBerjalan: await _shiftBerjalan(),
      shiftTerakhirDitutup: await _shiftTerakhirDitutup(awalHari),
    );
  }

  Future<List<ShiftBerjalan>> _shiftBerjalan() async {
    final shifts = await (_db.select(_db.shifts)
          ..where((s) => s.endAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.startAt)]))
        .get();
    if (shifts.isEmpty) return const [];

    final nama = await _db.namaAkun();
    // Satu kueri untuk semua shift, dan hanya jumlah & totalnya. Dulu satu
    // kueri per shift yang membawa SEMUA baris transaksinya (review E3).
    final baris = await _db
        .customSelect(
          'SELECT shift_id, COUNT(*) AS n, COALESCE(SUM(total), 0) AS jumlah '
          'FROM transactions WHERE deleted_at IS NULL AND shift_id IN '
          '(${List.filled(shifts.length, '?').join(', ')}) GROUP BY shift_id',
          variables: [for (final s in shifts) Variable.withString(s.id)],
          readsFrom: {_db.transactions},
        )
        .get();
    final perShift = {
      for (final b in baris)
        b.read<String>('shift_id'): (b.read<int>('n'), b.read<int>('jumlah')),
    };
    return [
      for (final s in shifts)
        ShiftBerjalan(
          namaKasir: s.namaKasir(nama) ?? 'Kasir',
          mulai: s.startAt,
          transaksi: perShift[s.id]?.$1 ?? 0,
          pendapatan: perShift[s.id]?.$2 ?? 0,
        ),
    ];
  }

  /// Kapan shift terakhir ditutup — hanya kalau masih HARI INI. Shift yang
  /// ditutup kemarin malam tidak relevan untuk "ringkasan hari ini".
  Future<DateTime?> _shiftTerakhirDitutup(DateTime awalHari) async {
    final s = await (_db.select(_db.shifts)
          ..where((s) =>
              s.endAt.isBiggerOrEqualValue(awalHari) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.endAt)])
          ..limit(1))
        .getSingleOrNull();
    return s?.endAt;
  }
}
