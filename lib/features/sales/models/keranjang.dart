import 'package:flutter/foundation.dart';

import '../../../data/models/sale_line.dart';

/// Pesanan yang sedang disusun kasir — SATU sumber untuk isi dan totalnya.
///
/// Halaman Kasir dan halaman Keranjang memakai objek yang sama, jadi tidak
/// ada salinan yang bisa berbeda. Barisnya langsung berbentuk [SaleLine],
/// bentuk yang dikirim ke `createSale`: total yang tampil di layar dan total
/// yang tersimpan memakai rumus yang sama, [SaleLine.subtotal].
///
/// Hanya logika — tampilan, animasi, dan pertanyaan level pedas tetap urusan
/// halaman.
class Keranjang extends ChangeNotifier {
  final List<SaleLine> _baris = [];

  /// Isi keranjang, urut sesuai saat dimasukkan. Tidak bisa diubah dari luar:
  /// setiap perubahan wajib lewat [Keranjang] supaya pendengarnya tahu.
  List<SaleLine> get baris => List.unmodifiable(_baris);

  int get jumlahBaris => _baris.length;
  bool get isEmpty => _baris.isEmpty;
  int get total => _baris.fold(0, (s, b) => s + b.subtotal);

  bool sudahAda(String idProduk) => _indeks(idProduk) != -1;

  /// Produk yang sudah ada menambah jumlahnya — harga dan catatannya tetap
  /// yang pertama kali dicatat. Produk baru masuk dengan jumlah satu.
  void tambah({
    required String idProduk,
    required String nama,
    required int harga,
    String? catatan,
  }) {
    final i = _indeks(idProduk);
    if (i != -1) {
      _baris[i] = _baris[i].copyWith(qty: _baris[i].qty + 1);
    } else {
      _baris.add(SaleLine(
        productId: idProduk,
        productName: nama,
        qty: 1,
        priceAtSale: harga,
        notes: catatan,
      ));
    }
    notifyListeners();
  }

  // Indeks di luar daftar diabaikan: tombol bisa tertekan dua kali sebelum
  // daftarnya digambar ulang.

  void tambahSatu(int indeks) {
    if (!_sah(indeks)) return;
    _baris[indeks] = _baris[indeks].copyWith(qty: _baris[indeks].qty + 1);
    notifyListeners();
  }

  /// Jumlah yang habis berarti barisnya dibuang.
  void kurangiSatu(int indeks) {
    if (!_sah(indeks)) return;
    final sisa = _baris[indeks].qty - 1;
    if (sisa <= 0) {
      _baris.removeAt(indeks);
    } else {
      _baris[indeks] = _baris[indeks].copyWith(qty: sisa);
    }
    notifyListeners();
  }

  void hapus(int indeks) {
    if (!_sah(indeks)) return;
    _baris.removeAt(indeks);
    notifyListeners();
  }

  void kosongkan() {
    if (_baris.isEmpty) return;
    _baris.clear();
    notifyListeners();
  }

  int _indeks(String idProduk) =>
      _baris.indexWhere((b) => b.productId == idProduk);

  bool _sah(int indeks) => indeks >= 0 && indeks < _baris.length;
}
