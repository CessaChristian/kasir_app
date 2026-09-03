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
/// terikat: produk menyimpan `categoryId`, dan [deleteCategory] ikut melepas
/// kategori dari produk yang memakainya.
class ProductRepository {
  final AppDatabase _db;

  ProductRepository(this._db);

  // ---- KATEGORI ----

  /// Kategori milik business aktif, urut nama. Yang sudah dihapus tidak ikut.
  Stream<List<Category>> watchCategories() => _db.watchCategories();

  /// Tambah kategori baru atau perbarui yang sudah ada.
  /// Butuh izin `manage_products`.
  Future<void> upsertCategory({
    required String id,
    required String name,
    int? iconCodepoint,
  }) =>
      _db.upsertCategory(id: id, name: name, iconCodepoint: iconCodepoint);

  /// Tandai kategori terhapus. Produk yang memakainya dilepas jadi tanpa
  /// kategori, bukan ikut terhapus.
  Future<void> deleteCategory(String id) => _db.deleteCategory(id);

  // ---- PRODUK ----

  /// Produk milik business aktif. Yang sudah dihapus tidak ikut.
  Stream<List<Product>> watchProducts() => _db.watchProducts();

  /// Tambah produk baru atau perbarui yang sudah ada.
  /// Butuh izin `manage_products`.
  Future<void> upsertProduct({
    required String id,
    required String name,
    required int price,
    String? barcode,
    String? categoryId,
    required bool hasSpicyOption,
    String? imagePath,
  }) =>
      _db.upsertProduct(
        id: id,
        name: name,
        price: price,
        barcode: barcode,
        categoryId: categoryId,
        hasSpicyOption: hasSpicyOption,
        imagePath: imagePath,
      );

  /// Tandai produk terhapus. Struk lama tetap utuh karena
  /// `transaction_items` menyimpan salinan nama dan harga saat transaksi.
  Future<void> deleteProduct(String id) => _db.deleteProduct(id);
}
