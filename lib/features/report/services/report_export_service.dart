import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/app_database.dart';
import '../../../data/db.dart';

class ReportExportService {
  /// Export laporan ke file Excel dan buka share dialog
  static Future<void> exportReport(
    ReportSummary report,
    List<EmployeeReportSummary> employeeReports, {
    bool isMonthly = false,
  }) async {
    final excel = Excel.createExcel();

    // ========================
    // Sheet 1: Ringkasan
    // ========================
    final ringkasan = excel['Ringkasan'];
    final periodLabel = isMonthly ? 'Bulanan' : 'Harian';
    _addHeader(ringkasan, 'Laporan $periodLabel', 0);
    ringkasan.appendRow([
      TextCellValue(isMonthly ? 'Periode' : 'Tanggal'),
      TextCellValue(
        isMonthly
            ? DateFormat('MMMM yyyy', 'id_ID').format(report.date)
            : DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(report.date),
      ),
    ]);
    ringkasan.appendRow([TextCellValue('')]);

    // Summary
    _addSubHeader(ringkasan, 'Ringkasan', ringkasan.maxRows);
    _addDataRow(ringkasan, ['Total Pesanan', '${report.totalOrders} transaksi']);
    _addDataRow(ringkasan, ['Total Pemasukan', _formatRp(report.totalIncome)]);
    ringkasan.appendRow([TextCellValue('')]);

    // Payment methods
    _addSubHeader(ringkasan, 'Metode Pembayaran', ringkasan.maxRows);
    _addTableHeader(ringkasan, ['Metode', 'Jumlah Transaksi', 'Total']);
    _addDataRow(ringkasan, ['Cash', '${report.cashOrders}', _formatRp(report.cashTotal)]);
    _addDataRow(ringkasan, ['QRIS', '${report.qrisOrders}', _formatRp(report.qrisTotal)]);

    // Column widths
    ringkasan.setColumnWidth(0, 25);
    ringkasan.setColumnWidth(1, 25);
    ringkasan.setColumnWidth(2, 20);

    // ========================
    // Sheet 2: Produk Terlaris
    // ========================
    final produk = excel['Produk Terlaris'];
    _addHeader(produk, 'Produk Terlaris', 0);
    _addTableHeader(produk, ['No', 'Nama Produk', 'Qty Terjual', 'Total Penjualan']);

    for (int i = 0; i < report.topProducts.length; i++) {
      final p = report.topProducts[i];
      produk.appendRow([
        IntCellValue(i + 1),
        TextCellValue(p.productName),
        IntCellValue(p.totalQty),
        TextCellValue(_formatRp(p.totalSales)),
      ]);
    }

    produk.setColumnWidth(0, 6);
    produk.setColumnWidth(1, 30);
    produk.setColumnWidth(2, 15);
    produk.setColumnWidth(3, 20);

    // ========================
    // Sheet 3: Daftar Transaksi (dengan detail item)
    // ========================
    final transaksi = excel['Daftar Transaksi'];
    _addHeader(transaksi, 'Daftar Transaksi', 0);
    _addTableHeader(transaksi, ['No', 'Waktu', 'Metode', 'Produk', 'Qty', 'Harga', 'Subtotal', 'Total Transaksi']);

    if (isMonthly) {
      // Group transactions by day for monthly report
      final Map<String, List<Transaction>> grouped = {};
      for (final tx in report.transactions) {
        final dayKey = DateFormat('yyyy-MM-dd').format(tx.createdAt);
        grouped.putIfAbsent(dayKey, () => []).add(tx);
      }

      final sortedDays = grouped.keys.toList()..sort();
      int txNo = 0;

      for (final dayKey in sortedDays) {
        final dayDate = DateTime.parse(dayKey);
        final dayLabel = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(dayDate);

        // Day separator row
        final sepRow = transaksi.maxRows;
        transaksi.appendRow([TextCellValue('📅 $dayLabel')]);
        for (int col = 0; col < 8; col++) {
          final cell = transaksi.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: sepRow));
          cell.cellStyle = CellStyle(
            bold: true,
            fontSize: 10,
            backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
            fontFamily: getFontFamily(FontFamily.Calibri),
          );
        }

        final dayTxList = grouped[dayKey]!;
        for (int i = 0; i < dayTxList.length; i++) {
          txNo++;
          final tx = dayTxList[i];
          final items = await db.getTransactionItems(tx.id);
          final timeStr = DateFormat('HH:mm').format(tx.createdAt);
          final methodStr = tx.paymentMethod == 'cash' ? 'Cash' : 'QRIS';

          if (items.isEmpty) {
            transaksi.appendRow([
              IntCellValue(txNo),
              TextCellValue(timeStr),
              TextCellValue(methodStr),
              TextCellValue('-'),
              TextCellValue('-'),
              TextCellValue('-'),
              TextCellValue('-'),
              TextCellValue(_formatRp(tx.total)),
            ]);
          } else {
            transaksi.appendRow([
              IntCellValue(txNo),
              TextCellValue(timeStr),
              TextCellValue(methodStr),
              TextCellValue(items[0].productName),
              IntCellValue(items[0].qty),
              TextCellValue(_formatRp(items[0].priceAtSale)),
              TextCellValue(_formatRp(items[0].subtotal)),
              TextCellValue(_formatRp(tx.total)),
            ]);

            for (int j = 1; j < items.length; j++) {
              transaksi.appendRow([
                TextCellValue(''),
                TextCellValue(''),
                TextCellValue(''),
                TextCellValue(items[j].productName),
                IntCellValue(items[j].qty),
                TextCellValue(_formatRp(items[j].priceAtSale)),
                TextCellValue(_formatRp(items[j].subtotal)),
                TextCellValue(''),
              ]);
            }
          }
        }
      }
    } else {
      // Daily report — flat list
      for (int i = 0; i < report.transactions.length; i++) {
        final tx = report.transactions[i];
        final items = await db.getTransactionItems(tx.id);
        final timeStr = DateFormat('HH:mm').format(tx.createdAt);
        final methodStr = tx.paymentMethod == 'cash' ? 'Cash' : 'QRIS';

        if (items.isEmpty) {
          transaksi.appendRow([
            IntCellValue(i + 1),
            TextCellValue(timeStr),
            TextCellValue(methodStr),
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue(_formatRp(tx.total)),
          ]);
        } else {
          transaksi.appendRow([
            IntCellValue(i + 1),
            TextCellValue(timeStr),
            TextCellValue(methodStr),
            TextCellValue(items[0].productName),
            IntCellValue(items[0].qty),
            TextCellValue(_formatRp(items[0].priceAtSale)),
            TextCellValue(_formatRp(items[0].subtotal)),
            TextCellValue(_formatRp(tx.total)),
          ]);

          for (int j = 1; j < items.length; j++) {
            transaksi.appendRow([
              TextCellValue(''),
              TextCellValue(''),
              TextCellValue(''),
              TextCellValue(items[j].productName),
              IntCellValue(items[j].qty),
              TextCellValue(_formatRp(items[j].priceAtSale)),
              TextCellValue(_formatRp(items[j].subtotal)),
              TextCellValue(''),
            ]);
          }
        }
      }
    }

    transaksi.setColumnWidth(0, 6);
    transaksi.setColumnWidth(1, 10);
    transaksi.setColumnWidth(2, 10);
    transaksi.setColumnWidth(3, 25);
    transaksi.setColumnWidth(4, 8);
    transaksi.setColumnWidth(5, 15);
    transaksi.setColumnWidth(6, 15);
    transaksi.setColumnWidth(7, 18);

    // ========================
    // Sheet 4: Per Karyawan
    // ========================
    if (employeeReports.isNotEmpty) {
      final karyawan = excel['Per Karyawan'];
      _addHeader(karyawan, 'Laporan Per Karyawan', 0);
      _addTableHeader(karyawan, ['No', 'Nama', 'Transaksi', 'Cash', 'QRIS', 'Total Pendapatan']);

      for (int i = 0; i < employeeReports.length; i++) {
        final e = employeeReports[i];
        karyawan.appendRow([
          IntCellValue(i + 1),
          TextCellValue(e.username),
          IntCellValue(e.totalTransactions),
          TextCellValue(_formatRp(e.cashTotal)),
          TextCellValue(_formatRp(e.qrisTotal)),
          TextCellValue(_formatRp(e.totalIncome)),
        ]);
      }

      karyawan.setColumnWidth(0, 6);
      karyawan.setColumnWidth(1, 20);
      karyawan.setColumnWidth(2, 12);
      karyawan.setColumnWidth(3, 18);
      karyawan.setColumnWidth(4, 18);
      karyawan.setColumnWidth(5, 20);
    }

    // Remove default Sheet1
    excel.delete('Sheet1');

    // Save file
    final dateStr = isMonthly
        ? DateFormat('yyyy-MM').format(report.date)
        : DateFormat('yyyy-MM-dd').format(report.date);
    final fileName = 'Laporan_${periodLabel}_$dateStr.xlsx';
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';
    final fileBytes = excel.save();

    if (fileBytes == null) throw Exception('Gagal membuat file Excel');

    final file = File(filePath);
    await file.writeAsBytes(fileBytes);

    // Share
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
        subject: 'Laporan $periodLabel $dateStr',
      ),
    );
  }

  // ========================
  // HELPER METHODS
  // ========================

  static String _formatRp(int amount) {
    final formatted = NumberFormat('#,###', 'id_ID').format(amount);
    return 'Rp $formatted';
  }

  static void _addHeader(Sheet sheet, String title, int row) {
    sheet.appendRow([
      TextCellValue(title),
    ]);
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cell.cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      fontFamily: getFontFamily(FontFamily.Calibri),
    );
  }

  static void _addSubHeader(Sheet sheet, String title, int row) {
    sheet.appendRow([TextCellValue(title)]);
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cell.cellStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontFamily: getFontFamily(FontFamily.Calibri),
    );
  }

  static void _addTableHeader(Sheet sheet, List<String> headers) {
    final row = sheet.maxRows;
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 10,
        fontFamily: getFontFamily(FontFamily.Calibri),
        backgroundColorHex: ExcelColor.fromHexString('#D9E2F3'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
  }

  static void _addDataRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }
}
