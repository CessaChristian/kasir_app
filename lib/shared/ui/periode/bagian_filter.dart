import 'package:flutter/material.dart';

/// Satu pilihan di [BagianFilter]. [kode] null = "Semua".
class OpsiFilter {
  final String? kode;
  final String label;
  final IconData? ikon;

  const OpsiFilter({required this.kode, required this.label, this.ikon});
}

/// Bagian pilihan tambahan di lembar periode (desain): "Metode pembayaran"
/// di Riwayat, "Kategori biaya" di Pengeluaran. Pilihan pertama selalu
/// "Semua" (kode null).
class BagianFilter {
  /// Judul lembarnya, mis. "Filter Riwayat".
  final String judulLembar;

  /// Judul bagian, mis. "Metode pembayaran".
  final String judul;
  final List<OpsiFilter> opsi;

  /// true = chip sama lebar memenuhi baris (metode bayar); false = chip
  /// selebar isinya dan digeser ke samping (kategori biaya).
  final bool lebarSama;

  const BagianFilter({
    required this.judulLembar,
    required this.judul,
    required this.opsi,
    required this.lebarSama,
  });

  /// Label untuk [kode]; kode tak dikenal dianggap "Semua".
  String labelDari(String? kode) =>
      opsi.firstWhere((o) => o.kode == kode, orElse: () => opsi.first).label;

  /// Metode pembayaran di Riwayat. Kode = `transactions.payment_method`.
  static const metodeBayar = BagianFilter(
    judulLembar: 'Filter Riwayat',
    judul: 'Metode pembayaran',
    lebarSama: true,
    opsi: [
      OpsiFilter(kode: null, label: 'Semua', ikon: Icons.apps_rounded),
      OpsiFilter(kode: 'cash', label: 'Tunai', ikon: Icons.payments_rounded),
      OpsiFilter(kode: 'qris', label: 'QRIS', ikon: Icons.qr_code_2_rounded),
    ],
  );
}
