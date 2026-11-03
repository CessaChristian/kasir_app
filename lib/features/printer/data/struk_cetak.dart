import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../utils/currency_formatter.dart';

/// Satu baris nota cetak. Disusun dulu sebagai teks supaya isi dan tata
/// letaknya bisa diuji tanpa printer; baru di [keEscPos] jadi perintah.
class BarisCetak {
  final String teks;
  final bool tengah;
  final bool tebal;

  /// Huruf kecil printer (Font B, 9×17 titik) — muat lebih banyak huruf
  /// per baris; lihat [kolomKecil].
  final bool kecil;

  const BarisCetak(
    this.teks, {
    this.tengah = false,
    this.tebal = false,
    this.kecil = false,
  });

  @override
  String toString() => teks;
}

/// Nota hanya untuk kertas 58 mm — satu-satunya ukuran yang muat di
/// printer portabel toko (keputusan owner 2026-11-01): lebar cetak 384
/// titik.
const titikKertas = 384;

/// Huruf per baris: huruf biasa 12 titik = 32, huruf kecil (Font B) 9
/// titik = 42.
const kolomNota = titikKertas ~/ 12;
const kolomKecil = titikKertas ~/ 9;

/// Isi nota transaksi [tx], mengikuti nota Kasir Pintar Pro yang dipakai
/// Teras Inn (keputusan owner 2026-11-01): logo, alamat, kasir & nomor nota,
/// tanggal-jam satu baris, item dengan harga satuan "@", subtotal, total,
/// pembayaran, ucapan, lalu WiFi pelanggan di tengah.
///
/// Logonya bukan bagian dari sini — gambar, lihat `logo_cetak.dart`.
/// Cetak ulang dari Riwayat memakai isi yang sama persis.
List<BarisCetak> susunStruk({
  required Transaction tx,
  required List<TransactionItem> items,
  required String? namaKasir,
}) {
  const kolom = kolomNota;
  final tunai = tx.paymentMethod == 'cash';
  final dibayar = tunai ? (tx.cashReceived ?? tx.total) : tx.total;
  final garis = BarisCetak('-' * kolom);
  final jumlahItem = items.fold(0, (n, i) => n + i.qty);
  return [
    ..._kepala(),
    const BarisCetak(''),
    ..._label('Kasir', namaKasir ?? '-', kolom),
    ..._label('No. Nota', tx.invoiceNo, kolom),
    if (tx.billName case final nama? when nama.isNotEmpty)
      ..._label('Pelanggan', nama, kolom),
    const BarisCetak(''),
    ..._kiriKanan(
      DateFormat('yyyy-MM-dd').format(tx.createdAt),
      DateFormat('HH:mm:ss').format(tx.createdAt),
      kolom,
    ),
    BarisCetak('=' * kolom),
    if (items.isEmpty) const BarisCetak('Tidak ada item', tengah: true),
    for (final item in items) ...[
      for (final b in bungkus(item.productName, kolom)) BarisCetak(b),
      if (item.notes case final c? when c.isNotEmpty)
        for (final b in bungkus(c, kolom - 1)) BarisCetak(' $b'),
      ..._kiriKanan(
        '${item.qty} x @${formatRupiah(item.priceAtSale)}',
        formatRupiah(item.subtotal),
        kolom,
      ),
    ],
    garis,
    ..._kiriKanan('Subtotal ($jumlahItem item)', formatRp(tx.total), kolom),
    garis,
    ..._kiriKanan('Total', formatRp(tx.total), kolom, tebal: true),
    garis,
    ..._kiriKanan(
      'Dibayar (${tunai ? 'TUNAI' : 'QRIS'})',
      formatRp(dibayar),
      kolom,
    ),
    if (tunai)
      ..._kiriKanan(
        'Kembalian',
        formatRp(tx.change ?? (dibayar - tx.total)),
        kolom,
      ),
    garis,
    const BarisCetak('Terima Kasih!', tengah: true, tebal: true),
    const BarisCetak('Selamat Menikmati', tengah: true),
    const BarisCetak(''),
    // Huruf biasa: huruf kecil (Font B) terlalu kecil di kertas (tes
    // owner 2026-11-01).
    for (final b in bungkus('WiFi : ${AppConstants.wifiNama}', kolom))
      BarisCetak(b, tengah: true),
    for (final b in bungkus('Password : ${AppConstants.wifiSandi}', kolom))
      BarisCetak(b, tengah: true),
  ];
}

/// Kertas percobaan dari halaman Printer: kepala nota dan keterangan
/// printernya. Garis pemisahnya harus pas satu baris — tanda lebar kertas
/// yang dipilih sudah benar.
List<BarisCetak> susunTestPrint({
  required String namaPrinter,
  required DateTime waktu,
}) {
  const kolom = kolomNota;
  return [
    ..._kepala(),
    BarisCetak('-' * kolom),
    ..._kiriKanan('Printer', namaPrinter, kolom),
    ..._kiriKanan('Waktu', DateFormat('yyyy-MM-dd HH:mm').format(waktu), kolom),
    BarisCetak('-' * kolom),
  ];
}

List<BarisCetak> _kepala() => const [
  BarisCetak(AppConstants.alamatNota, tengah: true),
  BarisCetak(AppConstants.storePhone, tengah: true),
];

/// "Kasir    : sari" — labelnya disejajarkan. Isi yang terlalu panjang
/// berlanjut di baris berikutnya, sejajar isinya.
List<BarisCetak> _label(String label, String isi, int kolom) {
  const lebarLabel = 9;
  final awal = '${label.padRight(lebarLabel)}: ';
  final baris = bungkus(isi, kolom - awal.length);
  return [
    for (var i = 0; i < baris.length; i++)
      BarisCetak((i == 0 ? awal : ' ' * awal.length) + baris[i]),
  ];
}

/// "kiri ........ kanan" dalam [kolom] huruf. Kalau tidak muat, [kiri]
/// dibungkus dan [kanan] turun ke baris sendiri, rata kanan — angka tidak
/// pernah terpotong.
List<BarisCetak> _kiriKanan(
  String kiri,
  String kanan,
  int kolom, {
  bool tebal = false,
}) {
  if (kiri.length + 1 + kanan.length <= kolom) {
    return [
      BarisCetak(
        kiri + ' ' * (kolom - kiri.length - kanan.length) + kanan,
        tebal: tebal,
      ),
    ];
  }
  return [
    for (final b in bungkus(kiri, kolom)) BarisCetak(b, tebal: tebal),
    for (final b in bungkus(kanan, kolom))
      BarisCetak(b.padLeft(kolom), tebal: tebal),
  ];
}

/// Pecah [teks] jadi baris selebar paling banyak [lebar] huruf, di spasi
/// kalau bisa; kata yang lebih panjang dari satu baris dipotong.
List<String> bungkus(String teks, int lebar) {
  final hasil = <String>[];
  var baris = '';
  for (var kata in teks.trim().split(RegExp(r'\s+'))) {
    while (kata.length > lebar) {
      if (baris.isNotEmpty) {
        hasil.add(baris);
        baris = '';
      }
      hasil.add(kata.substring(0, lebar));
      kata = kata.substring(lebar);
    }
    if (baris.isEmpty) {
      baris = kata;
    } else if (baris.length + 1 + kata.length <= lebar) {
      baris = '$baris $kata';
    } else {
      hasil.add(baris);
      baris = kata;
    }
  }
  if (baris.isNotEmpty || hasil.isEmpty) hasil.add(baris);
  return hasil;
}

/// Jarak kosong sebelum isi nota, dalam titik (8 titik ≈ 1 mm).
const jarakAtasTitik = 32;

/// Perintah ESC/POS untuk [baris], didahului [logo] (perintah gambar dari
/// `logo_cetak.dart`, kalau ada) dan diakhiri [umpan] baris kosong supaya
/// bagian bawah nota keluar dari printer dan bisa disobek.
List<int> keEscPos(List<BarisCetak> baris, {List<int>? logo, int umpan = 4}) {
  final b = <int>[
    0x1B, 0x40, // ESC @: mulai bersih
    // ESC J: majukan kertas ±4 mm dulu. Tanpa ini bagian atas logo
    // terpotong di RPP02N (tes owner 2026-11-01) — semua isi ikut turun.
    0x1B, 0x4A, jarakAtasTitik,
  ];
  if (logo != null) {
    b
      ..addAll(logo)
      ..add(0x0A);
  }
  for (final x in baris) {
    b
      ..addAll([0x1B, 0x61, x.tengah ? 1 : 0]) // ESC a: rata
      ..addAll([0x1B, 0x45, x.tebal ? 1 : 0]) // ESC E: tebal
      ..addAll([0x1B, 0x4D, x.kecil ? 1 : 0]) // ESC M: huruf A / B
      ..addAll(ascii.encode(hurufCetak(x.teks)))
      ..add(0x0A);
  }
  b
    ..addAll([0x1B, 0x61, 0, 0x1B, 0x45, 0, 0x1B, 0x4D, 0])
    ..addAll([0x1B, 0x64, umpan]); // ESC d: umpan kertas
  return b;
}

/// Printer thermal murah hanya mengenal huruf ASCII. Huruf beraksen
/// diganti huruf dasarnya, tanda baca umum diganti padanannya, sisanya '?'.
String hurufCetak(String teks) {
  const ganti = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
    'É': 'E',
    'Á': 'A',
    'Ó': 'O',
    'Ú': 'U',
    'Í': 'I',
    'Ñ': 'N',
    '–': '-',
    '—': '-',
    '·': '-',
    '×': 'x',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '…': '...',
  };
  final s = StringBuffer();
  for (final r in teks.runes) {
    final c = String.fromCharCode(r);
    if (r >= 0x20 && r < 0x7F) {
      s.write(c);
    } else {
      s.write(ganti[c] ?? '?');
    }
  }
  return s.toString();
}
