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
                child: Row(
                  children: [
                    for (var i = 0; i < kiri.length; i++) _tombol(kiri[i], i),
                    Expanded(child: _tombolTengah(iTengah)),
                    for (var i = 0; i < kanan.length; i++)
                      _tombol(kanan[i], iTengah + 1 + i),
                  ],
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

  Widget _tombol(ItemNav item, int indeks) {
    final aktif = indeks == terpilih;
    return Expanded(
      child: InkResponse(
        onTap: () => onPilih(indeks),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              aktif ? item.ikonAktif : item.ikon,
              size: 26,
              color: aktif ? WarnaTeras.oranye : WarnaTeras.ikonPasif,
            ),
            const SizedBox(height: 4),
            // Layar kecil dengan huruf besar: labelnya mengecil, bukan
            // terpotong "Pengelua…" dan menempel ke label sebelahnya (tes
            // alur 10 Nov). Jarak 2 px di kiri-kanan menjaga celahnya.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: TeksTeras.kecil,
                    fontWeight: aktif ? FontWeight.w700 : FontWeight.w400,
                    color: aktif ? WarnaTeras.teks : WarnaTeras.ikonPasif,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Label tombol tengah. Lingkarannya digambar di [build], di atas nav.
  Widget _tombolTengah(int indeks) {
    final aktif = indeks == terpilih;
    return GestureDetector(
      onTap: () => onPilih(indeks),
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(
            tengah.label,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
              color: WarnaTeras.teks,
            ),
          ),
        ),
      ),
    );
  }
}
