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

  test('produk sama dengan pilihan BERBEDA jadi baris baru', () {
    // Satu transaksi bisa berisi Mie Goreng "Sedang" dan Mie Goreng "Pedas".
    // Dulu keduanya tergabung jadi satu baris dengan catatan yang pertama.
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000,
        catatan: 'Pedas: Sedang');
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000,
        catatan: 'Pedas: Ekstra Pedas');
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000,
        catatan: 'Pedas: Sedang');

    expect(k.baris.map((b) => (b.notes, b.qty)), [
      ('Pedas: Sedang', 2),
      ('Pedas: Ekstra Pedas', 1),
    ]);
    expect(k.total, 45000);
  });

  test('tombol + di keranjang menambah baris itu dengan pilihan yang sama', () {
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000,
        catatan: 'Pedas: Sedang');
    k.tambah(idProduk: 'mie', nama: 'Mie', harga: 15000,
        catatan: 'Pedas: Pedas');
    k.tambahSatu(1);
    expect(k.baris[1].qty, 2);
    expect(k.baris[1].notes, 'Pedas: Pedas');
    expect(k.baris[0].qty, 1);
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
