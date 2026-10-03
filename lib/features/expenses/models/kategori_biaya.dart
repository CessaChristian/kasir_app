/// Kategori biaya pengeluaran (v32) — tiga pilihan tetap dari desain.
///
/// Disimpan sebagai [kode] di kolom `expenses.category` yang WAJIB diisi;
/// server dan HP sama-sama memagari nilainya dengan CHECK. Tidak ada
/// "Lainnya": pengeluaran lama dimasukkan ke Bahan Baku (keputusan owner
/// 2026-10-04), supaya tidak ada kategori yang tidak bisa dipilih di form.
enum KategoriBiaya {
  asset('asset', 'Asset'),
  bahanBaku('bahan_baku', 'Bahan Baku'),
  operasionalKedai('operasional_kedai', 'Operasional Kedai');

  final String kode;
  final String label;

  const KategoriBiaya(this.kode, this.label);

  static KategoriBiaya? dariKode(String kode) {
    for (final k in values) {
      if (k.kode == kode) return k;
    }
    return null;
  }

  /// Label untuk layar. Kode di luar tiga pilihan tidak mungkin lolos CHECK
  /// database; kalau pun ada, kodenya ditampilkan apa adanya.
  static String labelDari(String kode) => dariKode(kode)?.label ?? kode;
}
