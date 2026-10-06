import 'dart:isolate';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'dokumen_laporan.dart';

/// Seperti [buatExcelLaporan], tapi di isolate terpisah supaya layar tidak
/// membeku saat laporan besar dibuat.
Future<Uint8List> buatExcelLaporanDiLatar(DokumenLaporan dok) =>
    Isolate.run(() => buatExcelLaporan(dok));

/// Tulis [dok] sebagai file Excel: satu lembar per bagian.
///
/// Nominal ditulis sebagai ANGKA berformat Rupiah, bukan teks "Rp 15.000",
/// supaya bisa dijumlah, diurutkan, dan difilter di Excel.
Uint8List buatExcelLaporan(DokumenLaporan dok) {
  final excel = Excel.createExcel();
  final dibuat = DateFormat('dd/MM/yyyy HH:mm').format(dok.dibuat);

  for (final tabel in dok.tabel) {
    final sheet = excel[tabel.judul];
    _tulis(
      sheet,
      0,
      0,
      TextCellValue('${tabel.judul} — ${dok.namaToko}'),
      _gayaJudul,
    );
    _tulis(sheet, 0, 1, TextCellValue('Periode ${dok.labelPeriode}'), null);
    _tulis(
      sheet,
      0,
      2,
      TextCellValue('Dibuat $dibuat oleh ${dok.olehNama}'),
      _gayaKeterangan,
    );

    const barisKepala = 4;
    for (var c = 0; c < tabel.kolom.length; c++) {
      _tulis(sheet, c, barisKepala, TextCellValue(tabel.kolom[c]), _gayaKepala);
      sheet.setColumnWidth(c, tabel.lebar[c]);
    }
    for (var b = 0; b < tabel.baris.length; b++) {
      final baris = tabel.baris[b];
      final tebal = tabel.barisTebal.contains(b);
      for (var c = 0; c < baris.length; c++) {
        final (nilai, gaya) = switch (baris[c]) {
          SelTeks(:final teks) => (
            TextCellValue(teks) as CellValue,
            tebal ? _gayaTebal : null,
          ),
          SelAngka(:final nilai) => (
            IntCellValue(nilai),
            tebal ? _gayaAngkaTebal : _gayaAngka,
          ),
          SelRupiah(:final nilai) => (
            IntCellValue(nilai),
            tebal ? _gayaRupiahTebal : _gayaRupiah,
          ),
        };
        _tulis(sheet, c, barisKepala + 1 + b, nilai, gaya);
      }
    }
  }
  excel.delete('Sheet1');

  final bita = excel.save();
  if (bita == null) throw Exception('Gagal membuat file Excel');
  return Uint8List.fromList(bita);
}

void _tulis(
  Sheet sheet,
  int kolom,
  int baris,
  CellValue nilai,
  CellStyle? gaya,
) {
  final sel = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: kolom, rowIndex: baris),
  );
  sel.value = nilai;
  if (gaya != null) sel.cellStyle = gaya;
}

final _huruf = getFontFamily(FontFamily.Calibri);

final _gayaJudul = CellStyle(bold: true, fontSize: 14, fontFamily: _huruf);

final _gayaKeterangan = CellStyle(
  fontSize: 9,
  fontColorHex: ExcelColor.fromHexString('#8A817A'),
  fontFamily: _huruf,
);

final _gayaKepala = CellStyle(
  bold: true,
  fontSize: 10,
  backgroundColorHex: ExcelColor.fromHexString('#FDEBD8'),
  fontFamily: _huruf,
);

/// Baris total (mis. per bulan): tebal berlatar krem.
final _latarTebal = ExcelColor.fromHexString('#F7F1EB');

final _gayaTebal = CellStyle(
  bold: true,
  backgroundColorHex: _latarTebal,
  fontFamily: _huruf,
);

final _gayaAngkaTebal = CellStyle(
  bold: true,
  backgroundColorHex: _latarTebal,
  fontFamily: _huruf,
  numberFormat: const CustomNumericNumFormat(formatCode: '#,##0'),
);

final _gayaRupiahTebal = CellStyle(
  bold: true,
  backgroundColorHex: _latarTebal,
  fontFamily: _huruf,
  numberFormat: const CustomNumericNumFormat(formatCode: '"Rp" #,##0'),
);

final _gayaAngka = CellStyle(
  fontFamily: _huruf,
  numberFormat: const CustomNumericNumFormat(formatCode: '#,##0'),
);

final _gayaRupiah = CellStyle(
  fontFamily: _huruf,
  numberFormat: const CustomNumericNumFormat(formatCode: '"Rp" #,##0'),
);
