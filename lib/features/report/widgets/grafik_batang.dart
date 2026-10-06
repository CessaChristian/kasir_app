import 'package:flutter/material.dart';

import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/ringkasan_laporan.dart';

/// Grafik batang Tren Pendapatan (desain): batang tertinggi oranye, yang
/// berisi oranye muda, yang kosong abu dengan tinggi minimal.
///
/// Batang bisa diketuk: warnanya menggelap dan muncul gelembung berisi nama
/// ("Jam 08:00", "Sen, 1 Okt", "Okt 2026") dan nominalnya. Ketuk lagi untuk
/// menutup. Gelembung digambar di ATAS grafik — beri ruang ±50 di atasnya.
class GrafikBatang extends StatelessWidget {
  final List<BatangGrafik> batang;

  /// Indeks batang yang dipilih; null = tidak ada gelembung.
  final int? terpilih;
  final ValueChanged<int?> onPilih;

  const GrafikBatang({
    super.key,
    required this.batang,
    required this.terpilih,
    required this.onPilih,
  });

  static const tinggi = 130.0;
  static const _tinggiLabel = 14.0;
  static const _jarakLabel = 6.0;
  static const _lebarMaks = 26.0;
  static const _berisi = Color(0xFFF6D9BC);
  static const _kosong = Color(0xFFF1ECE7);
  static const _dipilih = Color(0xFFC96A12);

  @override
  Widget build(BuildContext context) {
    final maks = batang.fold(1, (m, b) => b.nilai > m ? b.nilai : m);
    final celah = batang.length > 16 ? 2.0 : 6.0;
    final pilih = terpilih != null && terpilih! < batang.length
        ? terpilih
        : null;
    return SizedBox(
      height: tinggi,
      child: LayoutBuilder(
        builder: (context, batas) {
          final n = batang.length;
          final lebarKolom = (batas.maxWidth - celah * (n - 1)) / n;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: celah),
                    Expanded(child: _kolom(i, maks, i == pilih)),
                  ],
                ],
              ),
              if (pilih != null)
                _gelembung(pilih, maks, lebarKolom, celah, batas.maxWidth),
            ],
          );
        },
      ),
    );
  }

  /// Tinggi batang sebagai bagian dari ruang batang — seperti desain:
  /// minimal 4% kalau berisi, 2% kalau nol.
  static double _persen(int nilai, int maks) =>
      nilai == 0 ? 0.02 : (nilai / maks).clamp(0.04, 1.0).toDouble();

  Widget _kolom(int i, int maks, bool dipilih) {
    final b = batang[i];
    final warna = dipilih
        ? _dipilih
        : b.nilai == 0
        ? _kosong
        : b.nilai == maks
        ? WarnaTeras.oranye
        : _berisi;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPilih(dipilih ? null : i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: FractionallySizedBox(
              heightFactor: _persen(b.nilai, maks),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _lebarMaks),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: warna,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                        bottom: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: _jarakLabel),
          SizedBox(
            height: _tinggiLabel,
            child: Text(
              b.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontSize: TeksTeras.keterangan - 1.5,
                color: WarnaTeras.teksPudar,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gelembung 6px di atas batang terpilih. Desain: dua batang paling kiri
  /// rata kiri, dua paling kanan rata kanan, sisanya di tengah — supaya
  /// tidak terpotong tepi kartu.
  Widget _gelembung(
    int i,
    int maks,
    double lebarKolom,
    double celah,
    double lebarTotal,
  ) {
    final b = batang[i];
    final n = batang.length;
    final ruangBatang = tinggi - _tinggiLabel - _jarakLabel;
    final lebarBatang = lebarKolom < _lebarMaks ? lebarKolom : _lebarMaks;
    final kiriKolom = i * (lebarKolom + celah);
    final kiriBatang = kiriKolom + (lebarKolom - lebarBatang) / 2;
    final bawah =
        _tinggiLabel + _jarakLabel + ruangBatang * _persen(b.nilai, maks) + 6;

    final isi = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: WarnaTeras.teks,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.nama,
            style: const TextStyle(
              fontSize: TeksTeras.keterangan - 1,
              color: Color(0xFFCFC6BD),
            ),
          ),
          Text(
            formatRp(b.nilai),
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (i < 2) {
      return Positioned(left: kiriBatang, bottom: bawah, child: isi);
    }
    if (i >= n - 2) {
      return Positioned(
        right: lebarTotal - (kiriBatang + lebarBatang),
        bottom: bawah,
        child: isi,
      );
    }
    // Tengah: titik tengah gelembung di titik tengah batang.
    return Positioned(
      left: kiriBatang + lebarBatang / 2,
      bottom: bawah,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: isi,
      ),
    );
  }
}
