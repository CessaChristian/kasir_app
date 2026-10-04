import 'package:flutter/material.dart';

/// Saringan metode pembayaran di filter Riwayat (desain: Semua / Tunai /
/// QRIS). [kode] = nilai `transactions.payment_method`; null untuk Semua.
enum MetodeFilter {
  semua('Semua', Icons.apps_rounded, null),
  tunai('Tunai', Icons.payments_rounded, 'cash'),
  qris('QRIS', Icons.qr_code_2_rounded, 'qris');

  final String label;
  final IconData ikon;
  final String? kode;

  const MetodeFilter(this.label, this.ikon, this.kode);

  bool cocok(String paymentMethod) => kode == null || kode == paymentMethod;
}
