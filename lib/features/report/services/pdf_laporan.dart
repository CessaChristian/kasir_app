import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../utils/currency_formatter.dart';
import 'dokumen_laporan.dart';

/// Huruf dan logo untuk PDF. Dimuat terpisah supaya test bisa memberinya
/// dari berkas, tanpa `rootBundle`.
class BahanPdf {
  final pw.Font biasa;
  final pw.Font tebal;
  final Uint8List? logo;

  const BahanPdf({required this.biasa, required this.tebal, this.logo});

  /// Roboto dari aset: huruf bawaan PDF tidak punya "–" dan "·".
  static Future<BahanPdf> muat() async {
    Future<pw.Font> huruf(String nama) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$nama'));
    final logo = await rootBundle.load('assets/images/Logo Teras Inn.png');
    return BahanPdf(
      biasa: await huruf('Roboto-Regular.ttf'),
      tebal: await huruf('Roboto-Bold.ttf'),
      logo: logo.buffer.asUint8List(),
    );
  }
}

const _oranye = PdfColor.fromInt(0xFFF08A2C);
const _kepala = PdfColor.fromInt(0xFFFDEBD8);
const _garis = PdfColor.fromInt(0xFFEFE8E1);
const _pudar = PdfColor.fromInt(0xFF8A817A);
const _teks = PdfColor.fromInt(0xFF1E1E1E);

/// Batas halaman per SATU widget (bukan per dokumen; hanya dicek di mode
/// debug). Bawaannya 20 — satu tabel raksasa pernah melewatinya
/// ("TooManyPagesException", Januari–Oktober di emulator). Pemotongan tabel
/// [barisPerPotongan] yang sebenarnya mencegahnya; ini hanya jaga-jaga.
const _halamanMaks = 5000;

/// Tabel panjang dipotong per sekian baris, tiap potongan mulai di halaman
/// baru. Satu tabel raksasa membuat paket `pdf` menghitung ulang sisa tabel
/// di setiap halaman: 3.000 transaksi butuh 16 detik, dipotong 2,3 detik.
/// Potongan dimulai di halaman baru supaya judul kolom selalu di atas
/// halaman, tidak pernah muncul di tengah.
const barisPerPotongan = 300;

/// Seperti [buatPdfLaporan], tapi di isolate terpisah supaya layar tidak
/// membeku saat laporan besar dibuat.
Future<Uint8List> buatPdfLaporanDiLatar(DokumenLaporan dok, BahanPdf bahan) =>
    Isolate.run(() => buatPdfLaporan(dok, bahan));

/// Tulis [dok] sebagai PDF A4: kepala halaman (logo, toko, periode), lalu
/// tiap bagian sebagai tabel; halaman bertambah sendiri dan bernomor.
/// Isinya sama dengan Excel. Teks panjang turun baris, tidak terpotong.
Future<Uint8List> buatPdfLaporan(DokumenLaporan dok, BahanPdf bahan) {
  final pdf = pw.Document(
    title: 'Laporan ${dok.namaToko} ${dok.labelPeriode}',
    author: dok.olehNama,
    theme: pw.ThemeData.withFont(base: bahan.biasa, bold: bahan.tebal),
  );
  final dibuat = DateFormat('dd/MM/yyyy HH:mm').format(dok.dibuat);
  final angka = NumberFormat('#,##0', 'id_ID');
  // Dibuat SEKALI: gambar yang dibuat di dalam kepala halaman tersimpan ulang
  // di setiap halaman (40 halaman = 40 salinan logo, PDF jadi 2,2 MB).
  final logo = bahan.logo == null ? null : pw.MemoryImage(bahan.logo!);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: _halamanMaks,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
      header: (konteks) => _kepalaHalaman(dok, logo),
      footer: (konteks) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Dibuat $dibuat oleh ${dok.olehNama}',
            style: const pw.TextStyle(fontSize: 7.5, color: _pudar),
          ),
          pw.Text(
            'Halaman ${konteks.pageNumber}/${konteks.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _pudar),
          ),
        ],
      ),
      build: (konteks) => [
        for (final (i, tabel) in dok.tabel.indexed) ...[
          // Tiap bagian mulai di halaman baru (seperti lembar Excel), supaya
          // judulnya tidak tertinggal sendirian di bawah halaman. Ringkasan
          // dan Per Hari/Jam berbagi halaman pembuka.
          if (i > 1) pw.NewPage(),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.only(left: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _oranye, width: 2)),
            ),
            child: pw.Text(
              tabel.judul,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          if (tabel.baris.isEmpty)
            _tabel(tabel, angka)
          else
            for (var i = 0; i < tabel.baris.length; i += barisPerPotongan) ...[
              if (i > 0) pw.NewPage(),
              _tabel(
                TabelLaporan(
                  judul: tabel.judul,
                  kolom: tabel.kolom,
                  lebar: tabel.lebar,
                  baris: tabel.baris.skip(i).take(barisPerPotongan).toList(),
                  barisTebal: {
                    for (final b in tabel.barisTebal)
                      if (b >= i && b < i + barisPerPotongan) b - i,
                  },
                ),
                angka,
              ),
            ],
        ],
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _kepalaHalaman(DokumenLaporan dok, pw.ImageProvider? logo) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _garis)),
    ),
    child: pw.Row(
      children: [
        if (logo != null) ...[
          pw.Image(logo, width: 28, height: 28),
          pw.SizedBox(width: 8),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                dok.namaToko,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Laporan Penjualan',
                style: const pw.TextStyle(fontSize: 9, color: _pudar),
              ),
            ],
          ),
        ),
        pw.Text(
          'Periode ${dok.labelPeriode}',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

const _latarTebal = PdfColor.fromInt(0xFFF7F1EB);

pw.Widget _tabel(TabelLaporan t, NumberFormat angka) {
  if (t.baris.isEmpty) {
    return pw.Text(
      'Tidak ada data pada periode ini.',
      style: const pw.TextStyle(fontSize: 8, color: _pudar),
    );
  }
  final kanan = <int>{
    for (final b in t.baris)
      for (var c = 0; c < b.length; c++)
        if (b[c] is! SelTeks) c,
  };
  pw.Widget sel(String teks, int kolom, {bool tebal = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      teks,
      textAlign: kanan.contains(kolom) ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 8,
        color: _teks,
        fontWeight: tebal ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
  String teks(Sel s) => switch (s) {
    SelTeks(:final teks) => teks,
    SelAngka(:final nilai) => angka.format(nilai),
    SelRupiah(:final nilai) => formatRp(nilai),
  };

  return pw.Table(
    columnWidths: {
      for (var c = 0; c < t.lebar.length; c++)
        c: pw.FlexColumnWidth(t.lebar[c]),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _garis, width: 0.5),
      bottom: pw.BorderSide(color: _garis, width: 0.5),
    ),
    children: [
      // Judul kolom diulang di atas setiap halaman.
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _kepala),
        children: [
          for (var c = 0; c < t.kolom.length; c++)
            sel(t.kolom[c], c, tebal: true),
        ],
      ),
      for (var b = 0; b < t.baris.length; b++)
        pw.TableRow(
          decoration: t.barisTebal.contains(b)
              ? const pw.BoxDecoration(color: _latarTebal)
              : null,
          children: [
            for (var c = 0; c < t.baris[b].length; c++)
              sel(teks(t.baris[b][c]), c, tebal: t.barisTebal.contains(b)),
          ],
        ),
    ],
  );
}
