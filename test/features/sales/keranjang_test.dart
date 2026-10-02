import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';

/// Keranjang belanja — SATU tempat untuk isi dan total pesanan.
///
/// Dulu keranjang hidup di dua halaman dengan dua model berbeda: halaman
/// Kasir menyimpan `_CartLine`, halaman Keranjang menyalinnya ke daftar
/// `CartItem` lalu menghitung totalnya sendiri. Rumus subtotal ada di tiga
/// tempat. Total yang tampil dan total yang tersimpan kini memakai rumus yang
/// sama: `SaleLine.subtotal`.
void main() {
  late Keranjang k;
  var diberiTahu = 0;

  setUp(() {
    k = Keranjang()..addListener(() => diberiTahu++);
    diberiTahu = 0;
  });

  test('produk baru masuk satu, produk yang sama menambah jumlah', () {
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    k.tambah(idProduk: 'teh', nama: 'Teh', harga: 5000, catatan: 'Pedas');

    expect(k.baris.map((b) => (b.productId, b.qty)), [('kopi', 2), ('teh', 1)]);
    expect(k.baris[1].notes, 'Pedas');
    expect(k.total, 21000);
    expect(k.jumlahBaris, 2);
    expect(diberiTahu, 3);
  });

  test('menambah produk yang sudah ada tidak mengubah catatannya', () {
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000, catatan: 'Level 3');
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000);
    expect(k.baris.single.notes, 'Level 3');
  });

  test('sudahAda dipakai halaman untuk memutuskan bertanya level pedas', () {
    expect(k.sudahAda('mie'), isFalse);
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000);
    expect(k.sudahAda('mie'), isTrue);
  });

  test('tambah satu, kurangi satu, dan hilang saat jumlahnya habis', () {
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    k.tambahSatu(0);
    expect(k.baris.single.qty, 2);

    k.kurangiSatu(0);
    expect(k.baris.single.qty, 1);

    k.kurangiSatu(0);
    expect(k.isEmpty, isTrue, reason: 'jumlah 0 berarti barisnya dibuang');
  });

  test('hapus satu baris dan kosongkan semua', () {
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    k.tambah(idProduk: 'teh', nama: 'Teh', harga: 5000);
    k.hapus(0);
    expect(k.baris.single.productId, 'teh');

    k.kosongkan();
    expect(k.isEmpty, isTrue);
    expect(k.total, 0);
  });

  test('indeks di luar daftar diabaikan, tidak melempar galat', () {
    // Tombol bisa ditekan dua kali cepat sebelum daftar digambar ulang.
    k.tambahSatu(3);
    k.kurangiSatu(3);
    k.hapus(3);
    expect(k.isEmpty, isTrue);
    expect(diberiTahu, 0);
  });

  test('daftar baris tidak bisa diubah dari luar', () {
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    expect(() => k.baris.clear(), throwsUnsupportedError,
        reason: 'perubahan wajib lewat Keranjang supaya pendengarnya tahu');
  });

  test('harga yang dicatat adalah harga saat dimasukkan', () {
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 8000);
    // Harga produk naik selagi pesanan disusun — baris yang sudah ada tetap.
    k.tambah(idProduk: 'kopi', nama: 'Kopi', harga: 9000);
    expect(k.baris.single.priceAtSale, 8000);
    expect(k.total, 16000);
  });
}
