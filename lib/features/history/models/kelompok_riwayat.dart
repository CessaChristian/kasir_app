import '../../../data/app_database.dart';
import '../../../shared/ui/periode/periode.dart';

/// Transaksi satu hari untuk pita di halaman Riwayat.
class HariRiwayat {
  final DateTime tanggal;

  /// Termasuk yang dibatalkan (tampil berlabel), terbaru dulu.
  final List<Transaction> isi;

  /// Hanya yang TIDAK dibatalkan.
  final int total;

  const HariRiwayat(this.tanggal, this.isi, this.total);
}

/// Saring lalu kelompokkan per hari, hari terbaru dulu.
///
/// [cari] mencocokkan nomor nota; [idCocokMenu] adalah transaksi yang berisi
/// menu bernama mengandung kata cari itu (lihat
/// `SalesRepository.idTransaksiBerisiMenu`).
List<HariRiwayat> kelompokkanRiwayat(
  List<Transaction> semua, {
  required Periode periode,

  /// Kode `payment_method` ('cash'/'qris'); null = semua metode.
  required String? metode,
  String cari = '',
  Set<String> idCocokMenu = const {},
}) {
  DateTime hari(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  final kata = cari.trim().toLowerCase();
  final kelompok = <DateTime, List<Transaction>>{};
  for (final t in semua) {
    final h = hari(t.createdAt);
    if (h.isBefore(periode.dari) || h.isAfter(periode.sampai)) continue;
    if (metode != null && t.paymentMethod != metode) continue;
    if (kata.isNotEmpty &&
        !t.invoiceNo.toLowerCase().contains(kata) &&
        !idCocokMenu.contains(t.id)) {
      continue;
    }
    kelompok.putIfAbsent(h, () => []).add(t);
  }

  final urut = kelompok.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final h in urut)
      HariRiwayat(
        h,
        kelompok[h]!..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        kelompok[h]!
            .where((t) => t.deletedAt == null)
            .fold(0, (a, t) => a + t.total),
      ),
  ];
}
