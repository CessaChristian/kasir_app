import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../utils/currency_formatter.dart';
import '../models/ringkasan_laporan.dart';

/// Ekspor Laporan satu periode ke Excel, lalu buka menu bagikan.
///
/// Isinya: Ringkasan, Produk (yang terjual), dan Daftar Transaksi beserta
/// itemnya. [denganPengeluaran] false untuk akun yang tidak boleh melihat
/// pengeluaran — baris pengeluaran dan laba kotor tidak ikut.
Future<void> eksporLaporanExcel(
  Periode periode,
  RingkasanLaporan r, {
  required bool denganPengeluaran,
}) async {
  final excel = Excel.createExcel();
  final label = labelPeriode(periode);

  // ---- Ringkasan ----
  final ringkasan = excel['Ringkasan'];
  _judul(ringkasan, 'Laporan $label');
  _baris(ringkasan, ['Periode', label]);
  _baris(ringkasan, ['Shift', '${r.jumlahShift}']);
  ringkasan.appendRow([TextCellValue('')]);
  _subjudul(ringkasan, 'Ringkasan');
  _baris(ringkasan, ['Pendapatan', formatRp(r.pendapatan)]);
  _baris(ringkasan, ['Transaksi', '${r.jumlahTransaksi}']);
  _baris(ringkasan, ['Rata-rata / transaksi', formatRp(r.rataRata)]);
  if (denganPengeluaran) {
    _baris(ringkasan, ['Pengeluaran', formatRp(r.pengeluaran)]);
    _baris(ringkasan, ['Laba kotor', formatRp(r.labaKotor)]);
  }
  ringkasan.appendRow([TextCellValue('')]);
  _subjudul(ringkasan, 'Metode Pembayaran');
  _kepala(ringkasan, ['Metode', 'Jumlah Transaksi', 'Total']);
  _baris(ringkasan, ['Tunai', '${r.tunai.jumlah}', formatRp(r.tunai.nilai)]);
  _baris(ringkasan, ['QRIS', '${r.qris.jumlah}', formatRp(r.qris.nilai)]);
  ringkasan.appendRow([TextCellValue('')]);
  _subjudul(ringkasan, 'Tipe Pesanan');
  _kepala(ringkasan, ['Tipe', 'Jumlah Transaksi', 'Total']);
  _baris(ringkasan, [
    'Dine In',
    '${r.dineIn.jumlah}',
    formatRp(r.dineIn.nilai),
  ]);
  _baris(ringkasan, [
    'Delivery',
    '${r.delivery.jumlah}',
    formatRp(r.delivery.nilai),
  ]);
  ringkasan
    ..setColumnWidth(0, 25)
    ..setColumnWidth(1, 25)
    ..setColumnWidth(2, 20);

  // ---- Produk (yang terjual, pendapatan terbesar dulu) ----
  final produk = excel['Produk'];
  _judul(produk, 'Pendapatan per Produk');
  _kepala(produk, ['No', 'Produk', 'Kategori', 'Terjual', 'Pendapatan']);
  final laku = r.perProduk.where((p) => p.terjual > 0).toList()
    ..sort((a, b) => b.nilai.compareTo(a.nilai));
  for (var i = 0; i < laku.length; i++) {
    final p = laku[i];
    produk.appendRow([
      IntCellValue(i + 1),
      TextCellValue(p.nama),
      TextCellValue(p.kategori),
      IntCellValue(p.terjual),
      TextCellValue(formatRp(p.nilai)),
    ]);
  }
  produk
    ..setColumnWidth(0, 6)
    ..setColumnWidth(1, 25)
    ..setColumnWidth(2, 18)
    ..setColumnWidth(3, 10)
    ..setColumnWidth(4, 18);

  // ---- Daftar Transaksi (lama ke baru, dipisah per hari) ----
  final transaksi = excel['Daftar Transaksi'];
  _judul(transaksi, 'Daftar Transaksi');
  _kepala(transaksi, [
    'No',
    'Waktu',
    'Metode',
    'Produk',
    'Qty',
    'Harga',
    'Subtotal',
    'Total Transaksi',
  ]);
  final urut = r.transaksi.reversed.toList();
  String? hariSebelumnya;
  for (var i = 0; i < urut.length; i++) {
    final tx = urut[i];
    final waktu = tx.createdAt.toLocal();
    if (!periode.satuHari) {
      final hari = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(waktu);
      if (hari != hariSebelumnya) {
        _pemisahHari(transaksi, hari);
        hariSebelumnya = hari;
      }
    }
    _transaksi(transaksi, i + 1, tx, r.item[tx.id] ?? const []);
  }
  for (final (kolom, lebar) in const [
    (0, 6.0),
    (1, 10.0),
    (2, 10.0),
    (3, 25.0),
    (4, 8.0),
    (5, 15.0),
    (6, 15.0),
    (7, 18.0),
  ]) {
    transaksi.setColumnWidth(kolom, lebar);
  }

  excel.delete('Sheet1');

  final tanggal = DateFormat('yyyy-MM-dd');
  final nama = periode.satuHari
      ? 'Laporan_${tanggal.format(periode.dari)}.xlsx'
      : 'Laporan_${tanggal.format(periode.dari)}_sd_'
            '${tanggal.format(periode.sampai)}.xlsx';
  final bita = excel.save();
  if (bita == null) throw Exception('Gagal membuat file Excel');
  final jalur = '${(await getTemporaryDirectory()).path}/$nama';
  await File(jalur).writeAsBytes(bita);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(jalur)], subject: 'Laporan $label'),
  );
}

void _transaksi(
  Sheet sheet,
  int no,
  Transaction tx,
  List<TransactionItem> isi,
) {
  final jam = TextCellValue(DateFormat('HH:mm').format(tx.createdAt.toLocal()));
  final metode = TextCellValue(tx.paymentMethod == 'qris' ? 'QRIS' : 'Tunai');
  final total = TextCellValue(formatRp(tx.total));
  if (isi.isEmpty) {
    sheet.appendRow([
      IntCellValue(no),
      jam,
      metode,
      for (var k = 0; k < 4; k++) TextCellValue('-'),
      total,
    ]);
    return;
  }
  for (var j = 0; j < isi.length; j++) {
    final i = isi[j];
    final pertama = j == 0;
    sheet.appendRow([
      pertama ? IntCellValue(no) : TextCellValue(''),
      pertama ? jam : TextCellValue(''),
      pertama ? metode : TextCellValue(''),
      TextCellValue(i.productName),
      IntCellValue(i.qty),
      TextCellValue(formatRp(i.priceAtSale)),
      TextCellValue(formatRp(i.subtotal)),
      pertama ? total : TextCellValue(''),
    ]);
  }
}

final _hurufCalibri = getFontFamily(FontFamily.Calibri);

void _judul(Sheet sheet, String teks) {
  final baris = sheet.maxRows;
  sheet.appendRow([TextCellValue(teks)]);
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: baris))
      .cellStyle = CellStyle(
    bold: true,
    fontSize: 14,
    fontFamily: _hurufCalibri,
  );
  sheet.appendRow([TextCellValue('')]);
}

void _subjudul(Sheet sheet, String teks) {
  final baris = sheet.maxRows;
  sheet.appendRow([TextCellValue(teks)]);
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: baris))
      .cellStyle = CellStyle(
    bold: true,
    fontSize: 11,
    fontFamily: _hurufCalibri,
  );
}

void _kepala(Sheet sheet, List<String> kolom) {
  final baris = sheet.maxRows;
  sheet.appendRow([for (final k in kolom) TextCellValue(k)]);
  for (var c = 0; c < kolom.length; c++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: baris))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#FDEBD8'),
      fontFamily: _hurufCalibri,
    );
  }
}

void _pemisahHari(Sheet sheet, String teks) {
  final baris = sheet.maxRows;
  sheet.appendRow([TextCellValue(teks)]);
  for (var c = 0; c < 8; c++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: baris))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#F7F1EB'),
      fontFamily: _hurufCalibri,
    );
  }
}

void _baris(Sheet sheet, List<String> nilai) =>
    sheet.appendRow([for (final v in nilai) TextCellValue(v)]);
