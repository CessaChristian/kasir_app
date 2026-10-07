import 'package:flutter/material.dart';

import '../../../shared/ui/baris_menu.dart';
import '../../../shared/ui/lembar_bawah.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';

/// Format file Laporan yang bisa dipilih (desain: PDF | Excel).
enum FormatLaporan {
  pdf(
    label: 'PDF',
    ekstensi: 'pdf',
    tulisan: 'PDF',
    mime: 'application/pdf',
    ikon: Icons.picture_as_pdf_rounded,
    warna: Color(0xFFD9483B),
    latar: Color(0xFFFCE7E4),
  ),
  excel(
    label: 'Excel',
    ekstensi: 'xlsx',
    tulisan: 'XLSX',
    mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ikon: Icons.table_chart_rounded,
    warna: WarnaTeras.hijau,
    latar: WarnaTeras.hijauMuda,
  );

  final String label;
  final String ekstensi;

  /// Tulisan kecil di bawah ikon kartu file.
  final String tulisan;
  final String mime;
  final IconData ikon;
  final Color warna;
  final Color latar;

  const FormatLaporan({
    required this.label,
    required this.ekstensi,
    required this.tulisan,
    required this.mime,
    required this.ikon,
    required this.warna,
    required this.latar,
  });
}

/// Lembar "Download Laporan": pilih PDF atau Excel (PDF terpilih bawaan,
/// desain). Null = Batal.
Future<FormatLaporan?> pilihFormatLaporan(
  BuildContext context, {
  required String labelPeriode,
}) {
  return tampilkanLembarBawah<FormatLaporan>(
    context,
    (context) => _PilihFormat(labelPeriode: labelPeriode),
  );
}

class _PilihFormat extends StatefulWidget {
  final String labelPeriode;

  const _PilihFormat({required this.labelPeriode});

  @override
  State<_PilihFormat> createState() => _PilihFormatState();
}

class _PilihFormatState extends State<_PilihFormat> {
  var _format = FormatLaporan.pdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JudulLembar(
          judul: 'Download Laporan',
          keterangan: 'Periode ${widget.labelPeriode}',
        ),
        const SizedBox(height: 16),
        const Text(
          'Pilih format file',
          style: TextStyle(
            fontSize: TeksTeras.kecil,
            color: WarnaTeras.teksPudar,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final f in FormatLaporan.values) ...[
              if (f != FormatLaporan.values.first) const SizedBox(width: 10),
              Expanded(child: _pilihan(f)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 10,
              child: TombolLembar(
                label: 'Batal',
                latar: WarnaTeras.latarAbu,
                warna: WarnaTeras.teks,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 16,
              child: TombolLembar(
                label: 'Download',
                ikon: Icons.download_rounded,
                latar: WarnaTeras.oranye,
                warna: Colors.white,
                onPressed: () => Navigator.pop(context, _format),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pilihan(FormatLaporan f) {
    final aktif = f == _format;
    return GestureDetector(
      onTap: () => setState(() => _format = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: aktif ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: aktif ? WarnaTeras.oranye : const Color(0xFFE6DED6),
            width: 1.5,
          ),
        ),
        child: Text(
          f.label,
          style: TextStyle(
            fontSize: TeksTeras.menu,
            fontWeight: FontWeight.w600,
            color: aktif ? WarnaTeras.oranye : WarnaTeras.teksSedang,
          ),
        ),
      ),
    );
  }
}

/// Pilihan di lembar "Laporan siap".
enum CaraSimpan { simpanKeHp, bagikan }

/// Lembar "Laporan siap": kartu file · Simpan ke HP · Bagikan · Batal.
/// Null = Batal.
Future<CaraSimpan?> tampilkanLaporanSiap(
  BuildContext context, {
  required FormatLaporan format,
  required String namaFile,
  required String keterangan,
}) {
  return tampilkanLembarBawah<CaraSimpan>(
    context,
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JudulLembar(
          judul: 'Laporan siap',
          keterangan: 'Pilih cara menyimpan laporan',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WarnaTeras.garis),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 48,
                decoration: BoxDecoration(
                  color: format.latar,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(format.ikon, size: 22, color: format.warna),
                    Text(
                      format.tulisan,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: format.warna,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      namaFile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w600,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      keterangan,
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BarisMenu(
          ikon: Icons.download_rounded,
          judul: 'Simpan ke HP',
          keterangan: 'Tersimpan di folder Download',
          latarIkon: WarnaTeras.oranyeMuda,
          onTap: () => Navigator.pop(context, CaraSimpan.simpanKeHp),
        ),
        const Divider(height: 1, color: WarnaTeras.garis),
        BarisMenu(
          ikon: Icons.share_rounded,
          judul: 'Bagikan',
          keterangan: 'Kirim lewat WhatsApp, email, dan lainnya',
          warnaIkon: WarnaTeras.biru,
          latarIkon: const Color(0xFFE8F0FB),
          onTap: () => Navigator.pop(context, CaraSimpan.bagikan),
        ),
        const SizedBox(height: 14),
        TombolLembar(
          label: 'Batal',
          latar: WarnaTeras.latarAbu,
          warna: WarnaTeras.teks,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

/// "248 KB" / "1,2 MB".
String ukuranBerkas(int bita) {
  if (bita < 1024 * 1024) return '${(bita / 1024).ceil()} KB';
  final mb = (bita / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
  return '$mb MB';
}
