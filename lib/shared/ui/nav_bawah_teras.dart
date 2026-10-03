import 'package:flutter/material.dart';

import 'warna_teras.dart';

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

  @override
  Widget build(BuildContext context) {
    final iTengah = kiri.length;
    return Container(
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
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w400,
                color: aktif ? WarnaTeras.teks : WarnaTeras.ikonPasif,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol bulat oranye yang menyembul ke atas nav.
  ///
  /// Lingkarannya sengaja keluar dari batas nav (`Clip.none`), bukan digeser
  /// dengan `Transform` — `Transform` tidak mengurangi ukuran tata letak,
  /// sehingga lingkaran + label melebihi tinggi nav ("BOTTOM OVERFLOWED").
  Widget _tombolTengah(int indeks) {
    final aktif = indeks == terpilih;
    return GestureDetector(
      onTap: () => onPilih(indeks),
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: -22,
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
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text(
                tengah.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                  color: WarnaTeras.teks,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
