import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/pegang_lembar.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/pilihan_produk.dart';

/// Hasil [tanyaPilihanProduk] saat kasir memilih "Lewati, tambah tanpa
/// varian": produk tetap masuk keranjang, tanpa catatan.
const tanpaVarian = '';

/// Lembar varian (desain): ditanyakan setiap kali produk yang punya pilihan
/// (Pedas / Manis / Es) diketuk.
///
/// Hasil: catatan untuk item struk, [tanpaVarian] kalau dilewati, atau null
/// kalau lembarnya ditutup — produk TIDAK dimasukkan ke keranjang.
Future<String?> tanyaPilihanProduk(BuildContext context, Product produk) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _PilihanProdukSheet(produk: produk),
  );
}

/// [catatan] hasil [tanyaPilihanProduk] menjadi catatan item keranjang.
String? catatanItem(String catatan) => catatan == tanpaVarian ? null : catatan;

class _PilihanProdukSheet extends StatefulWidget {
  final Product produk;
  const _PilihanProdukSheet({required this.produk});

  @override
  State<_PilihanProdukSheet> createState() => _PilihanProdukSheetState();
}

class _PilihanProdukSheetState extends State<_PilihanProdukSheet> {
  late final List<KelompokPilihan> _kelompok = kelompokUntuk(widget.produk);

  // Sudah tertanda pilihan bawaan — kasir cukup mengubah yang diminta.
  late final Map<KelompokPilihan, String> _pilihan = {
    for (final k in _kelompok) k: k.bawaan,
  };

  static IconData _ikon(KelompokPilihan k) => switch (k) {
    KelompokPilihan.pedas => Icons.local_fire_department_rounded,
    KelompokPilihan.manis => Icons.cookie_rounded,
    KelompokPilihan.es => Icons.ac_unit_rounded,
  };

  static Color _warna(KelompokPilihan k) => switch (k) {
    KelompokPilihan.pedas => WarnaTeras.merah,
    KelompokPilihan.manis => const Color(0xFFB7791F),
    KelompokPilihan.es => WarnaTeras.biru,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PegangLembar(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.produk.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatRp(widget.produk.price),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.oranye,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Pilih varian pesanan:',
              style: TextStyle(fontSize: 13, color: WarnaTeras.teksSamar),
            ),
            for (final k in _kelompok) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(_ikon(k), size: 18, color: _warna(k)),
                  const SizedBox(width: 6),
                  Text(
                    k.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                spacing: 6,
                children: [
                  for (final opsi in k.daftar) Expanded(child: _opsi(k, opsi)),
                ],
              ),
            ],
            const SizedBox(height: 22),
            TombolLembar(
              label: 'Tambah ke Keranjang',
              ikon: Icons.add_shopping_cart_rounded,
              latar: WarnaTeras.oranye,
              warna: Colors.white,
              tinggi: 46,
              sudut: 6,
              ukuranTeks: 15,
              beratTeks: FontWeight.w500,
              onPressed: () => Navigator.pop(context, catatanDari(_pilihan)),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, tanpaVarian),
              style: TextButton.styleFrom(
                foregroundColor: WarnaTeras.teksSamar,
              ),
              child: const Text(
                'Lewati, tambah tanpa varian',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opsi(KelompokPilihan k, String opsi) {
    final dipilih = _pilihan[k] == opsi;
    return Material(
      color: dipilih ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: dipilih ? WarnaTeras.oranye : const Color(0xFFDDD6CF),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _pilihan[k] = opsi),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                opsi,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: dipilih ? FontWeight.w600 : FontWeight.w400,
                  color: dipilih ? WarnaTeras.oranye : WarnaTeras.teks,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
