import '../../../data/app_database.dart';
import 'kategori_biaya.dart';

/// Pengeluaran satu hari untuk bagian "Rincian Pengeluaran".
class HariPengeluaran {
  final DateTime tanggal;

  /// Termasuk yang dibatalkan (tampil berlabel), terbaru dulu.
  final List<Expense> isi;

  /// Hanya yang TIDAK dibatalkan.
  final int total;

  const HariPengeluaran(this.tanggal, this.isi, this.total);
}

/// Isi halaman Pengeluaran owner untuk satu periode.
class RingkasanPengeluaran {
  final int total;
  final int jumlahItem;
  final int jumlahHari;

  /// (label kategori, total), terbesar dulu. Hanya yang tidak dibatalkan.
  final List<(String, int)> perKategori;

  /// Terbaru dulu. Hari yang isinya cuma pembatalan tetap tampil.
  final List<HariPengeluaran> perHari;

  const RingkasanPengeluaran({
    required this.total,
    required this.jumlahItem,
    required this.jumlahHari,
    required this.perKategori,
    required this.perHari,
  });

  bool get kosong => perHari.isEmpty;
}

/// Pengeluaran yang dibatalkan TIDAK dihitung di total, kategori, jumlah
/// item, maupun jumlah hari — tapi tetap muncul di rincian harinya.
///
/// [kategori] (kode, mis. 'bahan_baku') menyaring semuanya — total, bar,
/// dan rincian; null = semua kategori (filter "Kategori biaya" di desain).
RingkasanPengeluaran ringkasPengeluaran(
  List<Expense> masuk, {
  String? kategori,
}) {
  final semua = kategori == null
      ? masuk
      : masuk.where((e) => e.category == kategori).toList();
  final aktif = semua.where((e) => e.deletedAt == null).toList();
  DateTime hari(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  final perKategori = <String, int>{};
  for (final e in aktif) {
    final k = KategoriBiaya.labelDari(e.category);
    perKategori[k] = (perKategori[k] ?? 0) + e.amount;
  }

  final kelompok = <DateTime, List<Expense>>{};
  for (final e in semua) {
    kelompok.putIfAbsent(hari(e.createdAt), () => []).add(e);
  }
  final hariUrut = kelompok.keys.toList()..sort((a, b) => b.compareTo(a));

  return RingkasanPengeluaran(
    total: aktif.fold(0, (a, e) => a + e.amount),
    jumlahItem: aktif.length,
    jumlahHari: aktif.map((e) => hari(e.createdAt)).toSet().length,
    perKategori: perKategori.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2)),
    perHari: [
      for (final h in hariUrut)
        HariPengeluaran(
          h,
          kelompok[h]!..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          kelompok[h]!
              .where((e) => e.deletedAt == null)
              .fold(0, (a, e) => a + e.amount),
        ),
    ],
  );
}
