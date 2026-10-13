import '../../../data/app_database.dart';

/// Pilihan tombol "Tanpa Kategori" di Kasir. Bukan id kategori sungguhan
/// (id kategori selalu UUID, tidak pernah kosong).
const pilihanTanpaKategori = '';

/// Tombol kategori di Kasir: yang disembunyikan owner tidak ikut. Produknya
/// tetap tampil di "Semua" (keputusan owner 2026-10-13).
List<Category> kategoriDiKasir(List<Category> semua) => [
  for (final c in semua)
    if (c.tampilDiKasir) c,
];

/// Produk tanpa kategori — termasuk yang kategorinya sudah tidak ada.
bool _tanpaKategori(Product p, Set<String> idAda) =>
    p.categoryId == null || !idAda.contains(p.categoryId);

/// Tombol "Tanpa Kategori" hanya muncul kalau memang ada produknya.
bool adaProdukTanpaKategori(List<Product> produk, List<Category> semua) {
  final idAda = {for (final c in semua) c.id};
  return produk.any((p) => _tanpaKategori(p, idAda));
}

/// Produk untuk [pilihan]: null = Semua, [pilihanTanpaKategori], atau id
/// kategori. Kategori yang baru saja disembunyikan dianggap "Semua", supaya
/// kasir tidak terjebak di tombol yang sudah hilang.
List<Product> saringPerKategori(
  List<Product> produk,
  List<Category> semua,
  String? pilihan,
) {
  final efektif = pilihanEfektif(semua, pilihan);
  if (efektif == null) return produk;
  if (efektif == pilihanTanpaKategori) {
    final idAda = {for (final c in semua) c.id};
    return [
      for (final p in produk)
        if (_tanpaKategori(p, idAda)) p,
    ];
  }
  return [
    for (final p in produk)
      if (p.categoryId == efektif) p,
  ];
}

/// [pilihan] yang masih berlaku: id kategori yang tidak lagi punya tombol
/// menjadi null (Semua).
String? pilihanEfektif(List<Category> semua, String? pilihan) {
  if (pilihan == null || pilihan == pilihanTanpaKategori) return pilihan;
  return kategoriDiKasir(semua).any((c) => c.id == pilihan) ? pilihan : null;
}
