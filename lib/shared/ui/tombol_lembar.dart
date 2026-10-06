import 'package:flutter/material.dart';

import 'teks_teras.dart';

/// Tombol penuh di bagian bawah lembar dan dialog (desain), mis. [Batal]
/// abu dan [Hapus]/[Download]/[Simpan] berwarna.
///
/// Bawaan: tinggi 48, sudut 14, huruf 14 tebal (lembar konfirmasi dan
/// unduh). Dialog Pembatalan memakai sudut 12, dialog Pengeluaran sudut 8
/// dengan huruf lebih besar dan tidak tebal — sesuai desain masing-masing.
class TombolLembar extends StatelessWidget {
  final String label;
  final IconData? ikon;
  final Color latar;
  final Color warna;

  /// Null = nonaktif: warnanya memudar (desain: oranye pucat sebelum
  /// alasan pembatalan dipilih).
  final VoidCallback? onPressed;
  final double tinggi;
  final double sudut;
  final double ukuranTeks;
  final FontWeight beratTeks;

  const TombolLembar({
    super.key,
    required this.label,
    required this.latar,
    required this.warna,
    required this.onPressed,
    this.ikon,
    this.tinggi = 48,
    this.sudut = 14,
    this.ukuranTeks = TeksTeras.biasa,
    this.beratTeks = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    final teks = Text(
      label,
      style: TextStyle(fontSize: ukuranTeks, fontWeight: beratTeks),
    );
    return SizedBox(
      height: tinggi,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: latar,
          foregroundColor: warna,
          disabledBackgroundColor: latar.withValues(alpha: 0.35),
          disabledForegroundColor: warna,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(sudut),
          ),
        ),
        child: ikon == null
            ? teks
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ikon, size: 20),
                  const SizedBox(width: 6),
                  Flexible(child: teks),
                ],
              ),
      ),
    );
  }
}
