/// Ukuran huruf UI baru — SATU tempat pengaturan.
///
/// Angka di desain adalah piksel iPhone 390px dengan font SF; di Android
/// (Roboto) hasilnya terlihat lebih kecil, jadi semuanya dinaikkan ±1–2 dari
/// desain (keputusan user 2026-10-03). Kalau terasa terlalu kecil/besar,
/// ubah di sini saja.
abstract final class TeksTeras {
  /// Keterangan kecil: label "Transaksi", "vs kemarin…". Desain 10.
  static const keterangan = 12.0;

  /// Teks kecil: tanggal header, label nav, sub-pita. Desain 11.
  static const kecil = 12.5;

  /// Teks biasa: sapaan, status shift, tombol. Desain 12–13.
  static const biasa = 14.0;

  /// Angka di baris angka. Desain 14.
  static const angka = 16.0;

  /// Judul baris menu. Desain 15.
  static const menu = 16.0;

  /// Judul header. Desain 18.
  static const judul = 20.0;

  /// Angka utama, mis. Pendapatan hari ini. Desain 22.
  static const angkaBesar = 26.0;
}
