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

  /// Garis tepi, mis. tombol Batal bergaris di lembar Ubah Username.
  final Color? tepi;

  /// Latar saat nonaktif. Bawaan: [latar] dipudarkan.
  final Color? latarNonaktif;

  /// Warna teks/ikon saat nonaktif. Bawaan: [warna].
  final Color? warnaNonaktif;

  /// Jarak kosong di dalam tombol. Bawaan (null): jarak bawaan FilledButton,
  /// 24 di kiri-kanan — terlalu lebar untuk tombol kecil yang berjajar tiga.
  final EdgeInsetsGeometry? paddingDalam;

  /// Teks tidak pernah pindah baris; kalau tetap tidak muat, teks mengecil.
  final bool satuBaris;

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
    this.tepi,
    this.latarNonaktif,
    this.warnaNonaktif,
    this.paddingDalam,
    this.satuBaris = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget teks = satuBaris
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: ukuranTeks, fontWeight: beratTeks),
            ),
          )
        : Text(
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
          padding: paddingDalam,
          disabledBackgroundColor:
              latarNonaktif ?? latar.withValues(alpha: 0.35),
          disabledForegroundColor: warnaNonaktif ?? warna,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(sudut),
            side: tepi == null ? BorderSide.none : BorderSide(color: tepi!),
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
