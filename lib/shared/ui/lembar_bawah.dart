import 'package:flutter/material.dart';

import 'pegang_lembar.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// Lembar bawah bergaya desain baru: sudut 24, pegangan kecil terang, isi
/// bisa digulir dan naik mengikuti keyboard (lembar berisi kolom isian).
///
/// Dipakai lembar Download Laporan dan lembar Kelola Kasir.
Future<T?> tampilkanLembarBawah<T>(BuildContext context, WidgetBuilder isi) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const PegangLembar.kecil(), isi(context)],
          ),
        ),
      ),
    ),
  );
}

/// Judul + keterangan rata kiri di puncak lembar (desain).
class JudulLembar extends StatelessWidget {
  final String judul;
  final String keterangan;

  const JudulLembar({super.key, required this.judul, required this.keterangan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          judul,
          style: const TextStyle(
            fontSize: TeksTeras.judulBagian,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          keterangan,
          style: const TextStyle(
            fontSize: TeksTeras.biasa,
            color: WarnaTeras.teksPudar,
          ),
        ),
      ],
    );
  }
}

/// Ikon besar di tengah + judul + keterangan rata tengah (desain lembar
/// Ubah Username, Reset PIN).
class KepalaLembarIkon extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String keterangan;
  final Color warna;
  final Color latar;

  const KepalaLembarIkon({
    super.key,
    required this.ikon,
    required this.judul,
    required this.keterangan,
    this.warna = WarnaTeras.oranye,
    this.latar = WarnaTeras.oranyeMuda,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: latar,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(ikon, size: 28, color: warna),
        ),
        const SizedBox(height: 12),
        Text(
          judul,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.judulBagian,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          keterangan,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.biasa,
            height: 1.4,
            color: WarnaTeras.teksPudar,
          ),
        ),
      ],
    );
  }
}
