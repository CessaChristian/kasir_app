import '../../../data/app_database.dart';

/// Satu-satunya pintu akses data profil business.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
/// Lihat catatan lengkap soal alasan lapisan ini di `ProductRepository`.
class BusinessRepository {
  final AppDatabase _db;

  BusinessRepository(this._db);

  /// Ambil satu business berdasarkan id. Null kalau tidak ada.
  Future<BusinessesData?> getById(String id) =>
      (_db.select(_db.businesses)..where((b) => b.id.equals(id)))
          .getSingleOrNull();

  /// Perbarui profil business.
  ///
  /// Nama business TIDAK bisa diubah — hardcode dari kode.
  /// Field yang bernilai null dibiarkan apa adanya; khusus logo, kirim
  /// `logoPathSet: true` dengan `logoPath: null` untuk menghapusnya.
  Future<void> updateBusiness({
    required String id,
    String? address,
    String? phone,
    String? logoPath,
    bool logoPathSet = false,
  }) =>
      _db.updateBusiness(
        id: id,
        address: address,
        phone: phone,
        logoPath: logoPath,
        logoPathSet: logoPathSet,
      );
}
