import 'package:flutter/material.dart';

/// Tipe pesanan di keranjang. Take Away sudah digabung ke Dine In (v34).
enum TipePesanan {
  dineIn('dine_in', 'Dine In', Icons.restaurant_rounded),
  delivery('delivery', 'Delivery', Icons.delivery_dining_rounded);

  const TipePesanan(this.kode, this.label, this.ikon);

  /// Nilai yang disimpan di `transactions.order_type`.
  final String kode;
  final String label;
  final IconData ikon;
}

/// Metode pembayaran di keranjang.
enum MetodeBayar {
  tunai('cash', 'Tunai', Icons.payments_rounded),
  qris('qris', 'QRIS', Icons.qr_code_2_rounded);

  const MetodeBayar(this.kode, this.label, this.ikon);

  /// Nilai yang disimpan di `transactions.payment_method`.
  final String kode;
  final String label;
  final IconData ikon;
}

/// Nominal cepat di pembayaran tunai: uang pas, lalu pecahan bulat
/// berikutnya yang biasa diserahkan pelanggan (kelipatan 10 rb, 50 rb,
/// 100 rb di atas total), tanpa kembar. Contoh total 37.000 → 37.000,
/// 40.000, 50.000, 100.000.
List<int> nominalCepat(int total) {
  int bulatkan(int kelipatan) =>
      ((total + kelipatan - 1) ~/ kelipatan) * kelipatan;
  final hasil = <int>[total];
  for (final k in const [10000, 50000, 100000]) {
    final n = bulatkan(k);
    if (n > 0 && !hasil.contains(n)) hasil.add(n);
  }
  return hasil;
}

/// Keadaan uang yang diterima dibanding total.
enum StatusUang { kosong, kurang, pas, kembalian }

StatusUang statusUang(int total, int? diterima) {
  if (diterima == null) return StatusUang.kosong;
  if (diterima < total) return StatusUang.kurang;
  if (diterima == total) return StatusUang.pas;
  return StatusUang.kembalian;
}
