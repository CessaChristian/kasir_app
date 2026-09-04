/// Laporan kemajuan satu putaran sinkronisasi, untuk ditampilkan ke pengguna.
///
/// Menarik seribu baris lewat jaringan ponsel bisa memakan lebih dari semenit.
/// Tanpa laporan seperti ini, layar diam total dan pengguna menyimpulkan
/// aplikasinya menggantung — lalu menekan tombol berulang kali.
class KemajuanSync {
  /// 'menarik' atau 'mengirim'.
  final String tahap;

  /// Nama tabel yang sedang dikerjakan, mis. 'products'.
  final String entitas;

  /// Tabel ke berapa dari keseluruhan, mulai dari 1.
  final int entitasKe;
  final int totalEntitas;

  /// Baris yang sudah diproses untuk entitas ini, dan totalnya.
  final int baris;
  final int totalBaris;

  const KemajuanSync({
    required this.tahap,
    required this.entitas,
    required this.entitasKe,
    required this.totalEntitas,
    required this.baris,
    required this.totalBaris,
  });

  /// Nama tabel dalam bahasa yang dimengerti pemilik warung.
  String get namaRamah => const {
        'users': 'Akun',
        'categories': 'Kategori',
        'products': 'Produk',
        'shifts': 'Shift',
        'transactions': 'Transaksi',
        'transaction_items': 'Rincian transaksi',
        'expenses': 'Pengeluaran',
      }[entitas] ??
      entitas;

  /// 0.0–1.0 untuk keseluruhan proses, bukan hanya tabel ini.
  ///
  /// Tiap tabel dianggap berbobot sama. Itu tidak akurat — rincian transaksi
  /// jauh lebih banyak dari kategori — tapi jauh lebih baik daripada bilah
  /// yang melompat mundur saat berganti tabel.
  double get rasio {
    final selesai = (entitasKe - 1) / totalEntitas;
    final sebagian =
        totalBaris == 0 ? 0.0 : (baris / totalBaris) / totalEntitas;
    return (selesai + sebagian).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      '$tahap $namaRamah $baris/$totalBaris (tabel $entitasKe/$totalEntitas)';
}
