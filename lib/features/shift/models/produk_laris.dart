import '../../../data/app_database.dart';

/// Satu produk beserta jumlah terjualnya, untuk "Produk Paling Laris" dan
/// "Terlaris di Shift Terakhir".
class ProdukLaris {
  final String idProduk;

  /// Nama produk sekarang; nama di struk kalau produknya sudah dihapus.
  final String nama;
  final int terjual;

  /// Null kalau produknya sudah dihapus — tidak bisa dijual lagi.
  final Product? produk;

  const ProdukLaris({
    required this.idProduk,
    required this.nama,
    required this.terjual,
    this.produk,
  });

  String? get foto => produk?.imagePath;
}

/// Senin 00.00 di minggu [waktu]. "Produk Paling Laris" dihitung per minggu
/// kalender dan mulai dari nol lagi setiap Senin 00.00 (keputusan owner
/// 2026-10-13) — bukan "7 hari terakhir", yang tidak pernah kosong.
DateTime awalMinggu(DateTime waktu) =>
    DateTime(waktu.year, waktu.month, waktu.day - (waktu.weekday - 1));
