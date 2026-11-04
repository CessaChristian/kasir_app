import 'package:flutter/foundation.dart';

/// Pemuatan yang bisa tumpang tindih, tapi hanya hasil yang TERAKHIR
/// dimulai yang dipakai.
///
/// Dasbor owner memuat ulang setiap ada perubahan data dan setiap menit.
/// Dua pemuatan bisa berjalan bersamaan, dan yang dimulai lebih dulu bisa
/// selesai belakangan — angkanya yang sudah basi lalu menimpa yang baru,
/// sampai pemuatan berikutnya (revisi QA K6).
class PemuatTerakhir {
  var _ke = 0;

  /// Jalankan [muat]; [pakai] — atau [gagal] kalau [muat] melempar — hanya
  /// dipanggil kalau tidak ada pemuatan lain yang dimulai sesudahnya.
  ///
  /// Galat tidak pernah lolos: pemanggilnya timer dan aliran database, jadi
  /// dulu galatnya tak tertangani dan layar berputar selamanya (review D2).
  Future<void> jalankan<T>(
    Future<T> Function() muat,
    void Function(T hasil) pakai, {
    void Function(Object galat)? gagal,
  }) async {
    final ke = ++_ke;
    try {
      final hasil = await muat();
      if (ke == _ke) pakai(hasil);
    } catch (e) {
      debugPrint('[pemuat] $e');
      if (ke == _ke) gagal?.call(e);
    }
  }
}
