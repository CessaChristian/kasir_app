import '../../../data/app_database.dart';

/// Satu-satunya pintu akses data produk & kategori.
///
/// Halaman UI TIDAK boleh memanggil [AppDatabase] langsung. Semua lewat sini.
///
/// Kenapa lapisan ini ada:
/// UI cukup tahu "beri aku daftar produk" — bukan dari mana datanya. Saat
/// database pusat (Supabase) dipasang nanti, yang berubah hanya isi class ini:
///
/// ```dart
/// Stream<List<Product>> watchProducts() {
///   _tarikDariServerKalauOnline();  // segarkan cache lokal
///   return _db.watchProducts();     // UI tetap baca lokal → offline aman
/// }
/// ```
///
/// Halaman UI tidak perlu diubah sebaris pun.
///
/// Produk dan kategori digabung dalam satu repository karena keduanya saling
/// terikat: produk menyimpan `categoryId`, dan [simpanKategori] ikut melepas
/// kategori dari produk yang memakainya.
class ProductRepository {
  final AppDatabase _db;

  ProductRepository(this._db);

  // ---- KATEGORI ----

  /// Semua kategori, urut nama. Yang sudah dihapus tidak ikut.
  Stream<List<Category>> watchCategories() => _db.watchCategories();

  /// Simpan seluruh perubahan halaman Kategori sekaligus.
  /// Butuh izin `manage_categories`. Lihat [AppDatabase.simpanKategori].
  Future<void> simpanKategori({
    List<({String nama, int? ikon})> tambah = const [],
    Map<String, bool> tampil = const {},
    Map<String, ({String nama, int? ikon})> ubah = const {},
    List<String> hapus = const [],
  }) => _db.simpanKategori(
    tambah: tambah,
    tampil: tampil,
    ubah: ubah,
    hapus: hapus,
  );

  // ---- PRODUK ----

  /// Semua produk. Yang sudah dihapus tidak ikut.
  Stream<List<Product>> watchProducts() => _db.watchProducts();

  /// Tambah produk baru atau perbarui yang sudah ada.
  /// Butuh izin `manage_products`.
  Future<void> upsertProduct({
    required String id,
    required String name,
    required int price,
    String? categoryId,
    required bool hasSpicyOption,
    required bool hasSweetOption,
    required bool hasIceOption,
    String? imagePath,
  }) =>
      _db.upsertProduct(
        id: id,
        name: name,
        price: price,
        categoryId: categoryId,
        hasSpicyOption: hasSpicyOption,
        hasSweetOption: hasSweetOption,
        hasIceOption: hasIceOption,
        imagePath: imagePath,
      );

  /// Tandai produk terhapus. Struk lama tetap utuh karena
  /// `transaction_items` menyimpan salinan nama dan harga saat transaksi.
  Future<void> deleteProduct(String id) => _db.deleteProduct(id);
}
