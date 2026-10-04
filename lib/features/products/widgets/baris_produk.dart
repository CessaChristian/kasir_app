import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../shared/services/image_storage_service.dart';
import '../../../shared/ui/bulatan_pilihan.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../../sales/models/pilihan_produk.dart';

/// Satu baris di daftar Produk (desain): foto · nama · harga · kategori ·
/// bulatan pilihan · tombol hapus. Ketuk baris untuk mengedit.
class BarisProduk extends StatelessWidget {
  final Product produk;
  final String namaKategori;
  final IconData ikonKategori;
  final VoidCallback onEdit;
  final VoidCallback onHapus;

  const BarisProduk({
    super.key,
    required this.produk,
    required this.namaKategori,
    required this.ikonKategori,
    required this.onEdit,
    required this.onHapus,
  });

  @override
  Widget build(BuildContext context) {
    final kelompok = kelompokUntuk(produk);
    return Container(
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C230A).withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                FotoProduk(path: produk.imagePath, ukuran: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produk.name,
                        style: const TextStyle(
                          fontSize: TeksTeras.menu,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatRp(produk.price),
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _chipKategori(),
                          if (kelompok.isNotEmpty) ...[
                            Container(
                              width: 1,
                              height: 14,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              color: const Color(0xFFE0D9D2),
                            ),
                            for (final k in kelompok)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: BulatanPilihan(k),
                              ),
                            Flexible(
                              child: Text(
                                teksRingkasPilihan(kelompok),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: TeksTeras.kecil,
                                  color: WarnaTeras.teksPudar,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFFFFE9E7),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onHapus,
                    child: const SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 21,
                        color: WarnaTeras.merah,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipKategori() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFECE9E6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikonKategori, size: 14, color: WarnaTeras.teksSedang),
          const SizedBox(width: 3),
          Text(
            namaKategori,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.teksSedang,
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto produk berbingkai, atau kotak bergaris krem berikon gambar kalau
/// produk belum punya foto (desain).
class FotoProduk extends StatelessWidget {
  /// Path RELATIF yang tersimpan di database (lihat ImageStorageService).
  final String? path;
  final double ukuran;

  const FotoProduk({super.key, required this.path, required this.ukuran});

  @override
  Widget build(BuildContext context) {
    final ada = ImageStorageService.adaSync(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: ukuran,
        height: ukuran,
        child: ada
            ? Image.file(
                File(ImageStorageService.lokasiPenuhSync(path!)),
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => const _TanpaFoto(),
              )
            : const _TanpaFoto(),
      ),
    );
  }
}

class _TanpaFoto extends StatelessWidget {
  const _TanpaFoto();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GarisMiring(),
      child: const Center(
        child: Icon(Icons.image_rounded, size: 22, color: Color(0xFFC9B8A6)),
      ),
    );
  }
}

/// Garis miring krem selang-seling (desain: repeating-linear-gradient 135°,
/// pita 6px).
class _GarisMiring extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF6EDE3),
    );
    final pita = Paint()
      ..color = const Color(0xFFEFE4D8)
      ..strokeWidth = 6;
    // Jarak antar-pita 12px diukur tegak lurus garis 45°.
    const langkah = 12 * 1.4142;
    for (var x = -size.height; x < size.width; x += langkah) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), pita);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
