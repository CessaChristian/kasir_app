/// Pemuatan yang bisa tumpang tindih, tapi hanya hasil yang TERAKHIR
/// dimulai yang dipakai.
///
/// Dasbor owner memuat ulang setiap ada perubahan data dan setiap menit.
/// Dua pemuatan bisa berjalan bersamaan, dan yang dimulai lebih dulu bisa
/// selesai belakangan — angkanya yang sudah basi lalu menimpa yang baru,
/// sampai pemuatan berikutnya (revisi QA K6).
class PemuatTerakhir {
  var _ke = 0;

  /// Jalankan [muat]; [pakai] hanya dipanggil kalau tidak ada pemuatan lain
  /// yang dimulai sesudahnya.
  Future<void> jalankan<T>(
    Future<T> Function() muat,
    void Function(T hasil) pakai,
  ) async {
    final ke = ++_ke;
    final hasil = await muat();
    if (ke == _ke) pakai(hasil);
  }
}
