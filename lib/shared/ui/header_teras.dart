import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/business_logo.dart';
import 'warna_teras.dart';
import 'teks_teras.dart';

/// Header halaman di UI baru: logo (atau tombol kembali) · judul · tanggal.
///
/// Halaman utama (tab di nav bawah) memakai logo. Halaman turunan memberi
/// [onKembali], dan logonya diganti panah kembali. [aksi] adalah tombol di
/// kanan judul (refresh; nanti keranjang & bill di halaman Kasir).
///
/// [bertepi] menyalakan garis bawah samar saat isi halaman sudah di-scroll;
/// bayangannya digambar [BayanganHeader] di atas isi.
class HeaderTeras extends StatelessWidget {
  final String judul;
  final VoidCallback? onKembali;
  final List<Widget> aksi;
  final bool bertepi;

  const HeaderTeras({
    super.key,
    required this.judul,
    this.onKembali,
    this.aksi = const [],
    this.bertepi = false,
  });

  @override
  Widget build(BuildContext context) {
    final sekarang = DateTime.now();
    return AnimatedContainer(
      duration: _durasiTepi,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: WarnaTeras.latar,
        border: Border(
          bottom: BorderSide(
            color: bertepi
                ? _warnaBayangan.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onKembali != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: onKembali,
                icon: const Icon(Icons.arrow_back_rounded),
                color: WarnaTeras.teks,
                tooltip: 'Kembali',
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: BusinessLogo(size: 34),
            ),
          Expanded(
            child: Text(
              judul,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: TeksTeras.judul,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
          ),
          ...aksi,
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('EEEE', 'id_ID').format(sekarang),
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.teks,
                ),
              ),
              Text(
                DateFormat('d MMM yyyy', 'id_ID').format(sekarang),
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.teksSedang,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _durasiTepi = Duration(milliseconds: 250);

/// Cokelat bayangan di desain: rgba(60,35,10,…).
const _warnaBayangan = Color(0xFF3C230A);

/// Bayangan tipis di bawah header saat isi halaman sudah di-scroll.
///
/// Desain: `box-shadow: 0 6px 12px -6px rgba(60,35,10,.22)`. Digambar
/// sebagai gradasi di ATAS isi (taruh di puncak sebuah `Stack`), bukan sebagai
/// `boxShadow` header — isi halaman digambar sesudah header dan latarnya
/// akan menutupi bayangan itu.
class BayanganHeader extends StatelessWidget {
  final bool terlihat;

  const BayanganHeader({super.key, required this.terlihat});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: terlihat ? 1 : 0,
        duration: _durasiTepi,
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _warnaBayangan.withValues(alpha: 0.16),
                _warnaBayangan.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
