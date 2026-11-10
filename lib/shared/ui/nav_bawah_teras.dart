import 'package:flutter/material.dart';

import 'warna_teras.dart';
import 'teks_teras.dart';

/// Satu tombol di [NavBawahTeras].
class ItemNav {
  final IconData ikon;
  final IconData ikonAktif;
  final String label;

  const ItemNav({
    required this.ikon,
    required this.ikonAktif,
    required this.label,
  });
}

/// Nav bawah UI baru: tombol di kiri, satu tombol bulat besar di tengah,
/// tombol di kanan.
///
/// Urutan indeks mengikuti urutan tampil: [kiri], lalu [tengah], lalu
/// [kanan]. Owner dan kasir memakai widget yang sama dengan isi berbeda.
class NavBawahTeras extends StatelessWidget {
  final List<ItemNav> kiri;
  final ItemNav tengah;
  final List<ItemNav> kanan;
  final int terpilih;
  final ValueChanged<int> onPilih;

  const NavBawahTeras({
    super.key,
    required this.kiri,
    required this.tengah,
    required this.kanan,
    required this.terpilih,
    required this.onPilih,
  });

  /// Seberapa tinggi lingkaran tengah menyembul di atas nav.
  static const sembul = 22.0;

  /// Jarak label ke tepi bawah nav — sama untuk semua label.
  static const _jarakBawahLabel = 11.0;

  @override
  Widget build(BuildContext context) {
    final iTengah = kiri.length;
    final aktif = iTengah == terpilih;
    // Ruang sembulan ikut dihitung sebagai bagian nav. Dulu lingkarannya
    // digambar di luar batas nav, dan Flutter tidak meneruskan ketukan di
    // luar batas: 22 px bagian atas tombol Kasir tidak bisa diketuk (audit
    // 6 Nov nomor 53).
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: sembul),
          child: Container(
            decoration: const BoxDecoration(
              color: WarnaTeras.kartu,
              border: Border(top: BorderSide(color: WarnaTeras.garis)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 66,
                child: LayoutBuilder(
                  builder: (context, batas) {
                    final huruf = ukuranLabel(
                      lebarNav: batas.maxWidth,
                      label: [
                        for (final i in [...kiri, tengah, ...kanan]) i.label,
                      ],
                      skala: MediaQuery.textScalerOf(context),
                      gaya: DefaultTextStyle.of(context).style,
                    );
                    return Row(
                      children: [
                        for (var i = 0; i < kiri.length; i++)
                          _tombol(kiri[i], i, huruf),
                        Expanded(child: _tombolTengah(iTengah, huruf)),
                        for (var i = 0; i < kanan.length; i++)
                          _tombol(kanan[i], iTengah + 1 + i, huruf),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: GestureDetector(
            key: const ValueKey('nav-tengah-lingkaran'),
            onTap: () => onPilih(iTengah),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: WarnaTeras.oranye,
                shape: BoxShape.circle,
                border: Border.all(color: WarnaTeras.latar, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: WarnaTeras.oranye.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                aktif ? tengah.ikonAktif : tengah.ikon,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tombol(ItemNav item, int indeks, double huruf) {
    final aktif = indeks == terpilih;
    return Expanded(
      child: InkResponse(
        onTap: () => onPilih(indeks),
        // Ditempel ke garis bawah yang SAMA dengan label tengah
        // ([_jarakBawahLabel]), bukan di tengah kotak: begitu hurufnya
        // dikecilkan ([ukuranLabel]) dua cara itu bergeser berbeda dan label
        // tengah tampak lebih tinggi.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              aktif ? item.ikonAktif : item.ikon,
              size: 26,
              color: aktif ? WarnaTeras.oranye : WarnaTeras.ikonPasif,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: huruf,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w400,
                color: aktif ? WarnaTeras.teks : WarnaTeras.ikonPasif,
              ),
            ),
            const SizedBox(height: _jarakBawahLabel),
          ],
        ),
      ),
    );
  }

  /// Label tombol tengah. Lingkarannya digambar di [build], di atas nav.
  Widget _tombolTengah(int indeks, double huruf) {
    final aktif = indeks == terpilih;
    return GestureDetector(
      onTap: () => onPilih(indeks),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _jarakBawahLabel),
          child: Text(
            tengah.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: huruf,
              fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
              color: WarnaTeras.teks,
            ),
          ),
        ),
      ),
    );
  }
}

/// Isi halaman di atas [NavBawahTeras], untuk Scaffold dengan
/// `extendBody: true`.
///
/// Nav ikut menghitung ruang sembulan lingkaran tengah ([NavBawahTeras.sembul])
/// supaya bagian atas lingkaran bisa diketuk (audit 6 Nov nomor 53). Tanpa
/// ini halaman berhenti di atas ruang itu, dan pita 22 px berwarna latar
/// memotong isi halaman (tes alur 10 Nov). Di sini isinya menerus sampai
/// bagian putih nav: pita itu memperlihatkan isi halaman, dan ketukan di
/// luar lingkaran mengenai isi halaman.
class IsiDiAtasNav extends StatelessWidget {
  final Widget child;

  const IsiDiAtasNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Dengan extendBody, padding bawah = tinggi seluruh nav (termasuk ruang
    // sembulan dan area aman bawah HP).
    final tinggiNav = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        bottom: (tinggiNav - NavBawahTeras.sembul).clamp(0, double.infinity),
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

/// Ukuran huruf SEMUA label nav: [TeksTeras.kecil], atau lebih kecil kalau
/// label terpanjang tidak muat di kotaknya — semua label dikecilkan SAMA
/// besar.
///
/// Dulu tiap label mengecil sendiri (FittedBox): di HP yang "Pengeluaran"-nya
/// tidak muat — layar sempit, kerapatan tinggi, atau huruf HP diperbesar —
/// hanya label panjang yang mengecil, jadi ukuran huruf di nav tidak seragam
/// dan posisinya naik-turun (tes alur 10 Nov). Diukur dalam huruf TEBAL,
/// keadaan paling lebar (label yang sedang dipilih).
@visibleForTesting
double ukuranLabel({
  required double lebarNav,
  required List<String> label,
  required TextScaler skala,
  TextStyle gaya = const TextStyle(),
}) {
  if (label.isEmpty || lebarNav <= 0) return TeksTeras.kecil;
  // Jarak 4 px di kiri-kanan tiap kotak supaya label tidak saling menempel.
  final kotak = lebarNav / label.length - 8;
  var terlebar = 0.0;
  for (final l in label) {
    final p = TextPainter(
      text: TextSpan(
        text: l,
        style: gaya.copyWith(
          fontSize: TeksTeras.kecil,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: skala,
      maxLines: 1,
    )..layout();
    if (p.width > terlebar) terlebar = p.width;
    p.dispose();
  }
  if (terlebar <= kotak || kotak <= 0) return TeksTeras.kecil;
  return TeksTeras.kecil * kotak / terlebar;
}
