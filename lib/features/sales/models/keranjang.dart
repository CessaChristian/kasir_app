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

  /// Open bill yang sedang dimuat di keranjang; null = pesanan biasa. Lepas
  /// sendiri begitu keranjangnya kosong.
  BillAktif? _bill;
  BillAktif? get bill => _bill;

  /// Isi keranjang, urut sesuai saat dimasukkan. Tidak bisa diubah dari luar:
  /// setiap perubahan wajib lewat [Keranjang] supaya pendengarnya tahu.
  List<SaleLine> get baris => List.unmodifiable(_baris);

  int get jumlahBaris => _baris.length;
  bool get isEmpty => _baris.isEmpty;
  int get total => _baris.fold(0, (s, b) => s + b.subtotal);

  /// Produk yang SAMA dengan pilihan yang SAMA menambah jumlah baris itu —
  /// harganya tetap yang pertama kali dicatat. Pilihan berbeda (catatan
  /// berbeda) jadi baris baru: satu transaksi bisa berisi Mie Goreng "Sedang"
  /// dan Mie Goreng "Pedas".
  void tambah({
    required String idProduk,
    required String nama,
    required int harga,
    String? catatan,
  }) {
    final i = _baris.indexWhere(
        (b) => b.productId == idProduk && b.notes == catatan);
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

  // [baris] adalah baris yang dilihat kasir saat tombolnya ditekan. Indeks
  // saja tidak cukup: tombol bisa tertekan dua kali sebelum daftarnya
  // digambar ulang, dan sesudah satu baris dibuang, indeks yang sama sudah
  // menunjuk barang lain (audit 6 Nov nomor 32). Baris dicari menurut
  // produk dan catatannya; yang sudah tidak ada diabaikan.

  void tambahSatu(int indeks, {SaleLine? baris}) {
    final i = _cari(indeks, baris);
    if (i == null) return;
    _baris[i] = _baris[i].copyWith(qty: _baris[i].qty + 1);
    notifyListeners();
  }

  /// Jumlah yang habis berarti barisnya dibuang.
  void kurangiSatu(int indeks, {SaleLine? baris}) {
    final i = _cari(indeks, baris);
    if (i == null) return;
    final sisa = _baris[i].qty - 1;
    if (sisa <= 0) {
      _baris.removeAt(i);
    } else {
      _baris[i] = _baris[i].copyWith(qty: sisa);
    }
    _lepasKalauKosong();
    notifyListeners();
  }

  void hapus(int indeks, {SaleLine? baris}) {
    final i = _cari(indeks, baris);
    if (i == null) return;
    _baris.removeAt(i);
    _lepasKalauKosong();
    notifyListeners();
  }

  int? _cari(int indeks, SaleLine? harap) {
    bool sama(SaleLine b) =>
        harap == null ||
        (b.productId == harap.productId && b.notes == harap.notes);
    if (indeks >= 0 && indeks < _baris.length && sama(_baris[indeks])) {
      return indeks;
    }
    if (harap == null) return null;
    final i = _baris.indexWhere(sama);
    return i == -1 ? null : i;
  }

  /// Kosongkan isi sekaligus melepas open bill yang dimuat.
  void kosongkan() {
    if (_baris.isEmpty && _bill == null) return;
    _baris.clear();
    _bill = null;
    notifyListeners();
  }

  /// Ganti seluruh isi keranjang dengan isi open bill [bill].
  void muatBill(BillAktif bill, List<SaleLine> baris) {
    _baris
      ..clear()
      ..addAll(baris);
    _bill = bill;
    _lepasKalauKosong();
    notifyListeners();
  }

  /// Isi dan open bill keranjang sebagai JSON — untuk disimpan di HP supaya
  /// pesanan tidak hilang kalau aplikasinya dimatikan (simpanan_keranjang).
  Map<String, Object?> keJson() => {
    'baris': [
      for (final b in _baris)
        {
          'id': b.productId,
          'nama': b.productName,
          'qty': b.qty,
          'harga': b.priceAtSale,
          'catatan': b.notes,
        },
    ],
    'bill': _bill == null
        ? null
        : {'id': _bill!.id, 'nama': _bill!.nama, 'isiAwal': _bill!.isiAwal},
  };

  /// Kebalikan [keJson]. Hanya untuk keranjang yang masih kosong — pesanan
  /// yang sudah mulai disusun tidak ditimpa simpanan lama. False kalau
  /// isinya tidak terbaca atau keranjangnya sudah berisi.
  bool pulihkanDari(Map<String, Object?> json) {
    if (!isEmpty) return false;
    try {
      final baris = [
        for (final b in json['baris'] as List)
          SaleLine(
            productId: (b as Map)['id'] as String,
            productName: b['nama'] as String,
            qty: b['qty'] as int,
            priceAtSale: b['harga'] as int,
            notes: b['catatan'] as String?,
          ),
      ];
      final bill = json['bill'] as Map?;
      if (baris.isEmpty) return false;
      _baris.addAll(baris);
      _bill = bill == null
          ? null
          : (
              id: bill['id'] as String,
              nama: bill['nama'] as String,
              isiAwal: bill['isiAwal'] as String,
            );
    } catch (_) {
      _baris.clear();
      _bill = null;
      return false;
    }
    notifyListeners();
    return true;
  }

  // Keranjang kosong tidak bisa "memperbarui" bill — bill-nya tetap utuh di
  // daftar Open Bill.
  void _lepasKalauKosong() {
    if (_baris.isEmpty) _bill = null;
  }

}

/// Open bill yang sedang ada di keranjang. [isiAwal] = isi bill (JSON
/// `open_bills.items`) saat dimuat — patokan untuk menghitung apa yang
/// diubah di HP ini waktu bill diperbarui (`gabungIsiBill`).
typedef BillAktif = ({String id, String nama, String isiAwal});
