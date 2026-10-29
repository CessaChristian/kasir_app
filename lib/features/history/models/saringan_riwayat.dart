import '../../../shared/auth/cakupan_riwayat.dart';
import '../../../shared/ui/periode/periode.dart';

/// Apa yang sedang dilihat di halaman Riwayat: cakupan akun, periode
/// (null = semua tanggal), metode bayar (null = semua), dan kata cari.
///
/// Semuanya disaring di DATABASE (QA kedua K8) — dulu seluruh transaksi
/// sepanjang masa dibaca ke memori lalu disaring di aplikasi, setiap kali
/// ada data yang berubah.
class SaringanRiwayat {
  final CakupanRiwayat cakupan;
  final Periode? periode;
  final String? metode;
  final String cari;

  const SaringanRiwayat({
    required this.cakupan,
    this.periode,
    this.metode,
    this.cari = '',
  });

  /// Ada saringan dari pemakai (bukan sekadar cakupan & periode)?
  bool get disaring => metode != null || cari.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is SaringanRiwayat &&
      other.cakupan == cakupan &&
      other.periode?.dari == periode?.dari &&
      other.periode?.sampai == periode?.sampai &&
      other.metode == metode &&
      other.cari == cari;

  @override
  int get hashCode =>
      Object.hash(cakupan, periode?.dari, periode?.sampai, metode, cari);
}

/// Satu pita tanggal di Riwayat: jumlah transaksi (termasuk yang
/// dibatalkan, yang tetap tampil) dan totalnya (tanpa yang dibatalkan).
class RingkasanHari {
  final DateTime tanggal;
  final int jumlah;
  final int total;

  const RingkasanHari(this.tanggal, this.jumlah, this.total);
}
