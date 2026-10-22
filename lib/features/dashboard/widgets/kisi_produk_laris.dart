import 'package:flutter/material.dart';

import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../products/widgets/baris_produk.dart';
import '../../shift/models/produk_laris.dart';

/// Judul bagian dashboard (desain: 17, tebal).
class JudulDasbor extends StatelessWidget {
  final String teks;
  final String? keterangan;

  const JudulDasbor(this.teks, {super.key, this.keterangan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 22, bottom: keterangan == null ? 10 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            teks,
            style: const TextStyle(
              fontSize: TeksTeras.judulBagian,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teks,
            ),
          ),
          if (keterangan != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                keterangan!,
                style: const TextStyle(
                  fontSize: 12,
                  color: WarnaTeras.teksPudar,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Produk Paling Laris" minggu ini (desain): kisi 2 kolom berfoto, atau
/// kartu "Belum ada produk terjual" sesudah reset Senin.
///
/// [onPilih] null = hanya dilihat (owner); kasir mengetuk untuk menambah ke
/// keranjang.
///
/// Tinggi foto mengikuti tinggi layar ([tinggiFoto]): di layar acuan 120,
/// di layar pendek lebih rendah supaya keempat produk tetap terlihat.
class KisiProdukLaris extends StatelessWidget {
  final List<ProdukLaris> daftar;
  final void Function(ProdukLaris p)? onPilih;

  const KisiProdukLaris({super.key, required this.daftar, this.onPilih});

  /// Tinggi foto untuk layar setinggi [tinggiLayar] dp: 120 di layar acuan
  /// (±914 dp), menyusut di layar pendek, paling rendah 80 (lebih rendah
  /// lagi fotonya terlalu gepeng — lebih baik halaman digulir sedikit).
  static double tinggiFoto(double tinggiLayar) =>
      (tinggiLayar * 0.1315).clamp(80.0, 120.0);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JudulDasbor('Produk Paling Laris'),
        if (daftar.isEmpty)
          const _BelumAda()
        else
          LayoutBuilder(
            builder: (context, ukuran) {
              final lebar = (ukuran.maxWidth - 10) / 2;
              final foto = tinggiFoto(MediaQuery.sizeOf(context).height);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in daftar)
                    SizedBox(width: lebar, child: _kartu(p, foto)),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _kartu(ProdukLaris p, double foto) {
    final isi = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FotoProduk(
          path: p.foto,
          ukuran: foto,
          lebar: double.infinity,
          sudut: 0,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.thumb_up_rounded,
                    size: 15,
                    color: WarnaTeras.oranye,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      p.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: WarnaTeras.oranyeLembut,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Terjual ${p.terjual}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: WarnaTeras.oranye,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: WarnaTeras.kartu,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: onPilih == null
          ? isi
          : InkWell(onTap: () => onPilih!(p), child: isi),
    );
  }
}

class _BelumAda extends StatelessWidget {
  const _BelumAda();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: WarnaTeras.oranyeLembut,
            child: Icon(
              Icons.inventory_2_outlined,
              size: 26,
              color: WarnaTeras.oranye,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Belum ada produk terjual',
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teks,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Produk paling laris minggu ini muncul setelah ada transaksi. '
            'Dihitung ulang setiap Senin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
          ),
        ],
      ),
    );
  }
}
