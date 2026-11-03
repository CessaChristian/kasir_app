import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/printer/data/logo_cetak.dart';
import 'package:kasir_app/features/printer/data/struk_cetak.dart';

/// Nota cetak printer thermal — mengikuti nota Kasir Pintar Pro yang
/// dipakai Teras Inn (desain revisi 4, 2026-11-01).
void main() {
  final waktu = DateTime(2026, 11, 1, 0, 49, 7);

  Transaction tx({
    String metode = 'cash',
    int? diterima = 50000,
    String? bill = 'Meja 4',
    DateTime? batal,
    String jenis = 'dine_in',
  }) => Transaction(
    id: 't-1',
    invoiceNo: 'CS/01/231026/I-0001',
    createdAt: waktu,
    total: 46000,
    paymentMethod: metode,
    cashReceived: diterima,
    orderType: jenis,
    billName: bill,
    updatedAt: waktu,
    deletedAt: batal,
    syncStatus: 'synced',
  );

  TransactionItem item(String nama, int qty, int harga, [String? catatan]) =>
      TransactionItem(
        id: 'i-$nama',
        transactionId: 't-1',
        productId: 'p-$nama',
        productName: nama,
        qty: qty,
        priceAtSale: harga,
        subtotal: qty * harga,
        notes: catatan,
        createdAt: waktu,
        updatedAt: waktu,
        syncStatus: 'synced',
      );

  final items = [
    item('Kentang Goreng', 2, 12000),
    item('Es Kopi Susu Gula Aren', 1, 22000, 'less sugar, es dikit'),
  ];

  List<String> teks(List<BarisCetak> b) => [for (final x in b) x.teks];

  test('nota 58 mm sesuai desain revisi 4', () {
    final b = susunStruk(tx: tx(), items: items, namaKasir: 'sari');
    expect(teks(b), [
      'Jl. Kemiri Candi',
      '087859665084',
      '',
      'Kasir    : sari',
      'No. Nota : CS/01/231026/I-0001',
      'Pesanan  : Dine In',
      '',
      '2026-11-01              00:49:07',
      '=' * 32,
      'Kentang Goreng',
      '2 x @12.000               24.000',
      'Es Kopi Susu Gula Aren',
      ' less sugar, es dikit',
      '1 x @22.000               22.000',
      '-' * 32,
      'Subtotal (3 item)      Rp 46.000',
      '-' * 32,
      'Total                  Rp 46.000',
      '-' * 32,
      'Dibayar (TUNAI)        Rp 50.000',
      'Kembalian               Rp 4.000',
      '-' * 32,
      'Terima Kasih!',
      'Selamat Menikmati',
      '',
      'WiFi : TERAS INN',
      'Password : terasinspirasi',
    ]);
    final wifi = b.where((x) => x.teks.startsWith('WiFi') ||
        x.teks.startsWith('Password'));
    expect(wifi.every((x) => !x.kecil && x.tengah), isTrue,
        reason: 'WiFi huruf biasa, di tengah (tes owner 2026-11-01)');
    expect(b.singleWhere((x) => x.teks.startsWith('Total')).tebal, isTrue);
    for (final x in b) {
      expect(x.teks.length, lessThanOrEqualTo(x.kecil ? 42 : 32),
          reason: x.teks);
    }
  });

  test('QRIS tanpa kembalian; transaksi batal dicetak tanpa tanda apa pun',
      () {
    final t = teks(susunStruk(
      tx: tx(metode: 'qris', diterima: null, bill: null, batal: waktu),
      items: items,
      namaKasir: 'sari',
    ));
    expect(t, contains('Dibayar (QRIS)         Rp 46.000'));
    expect(t.where((x) => x.contains('Kembalian')), isEmpty);
    expect(t, contains('Pesanan  : Dine In'),
        reason: 'tipe pesanan selalu dicetak, dengan atau tanpa open bill');
    expect(t.where((x) => x.contains('BATAL') || x.contains('ULANG')), isEmpty,
        reason: 'keputusan owner 2026-11-01');
  });

  test('tipe pesanan menggantikan nama open bill (keputusan owner '
      '2026-11-03)', () {
    final t = teks(susunStruk(
      tx: tx(jenis: 'delivery', bill: 'Meja 4'),
      items: items,
      namaKasir: 'sari',
    ));
    expect(t, contains('Pesanan  : Delivery'));
    expect(t.where((x) => x.contains('Pelanggan') || x.contains('Meja 4')),
        isEmpty);
  });

  test('nama menu, catatan, dan nama kasir panjang dibungkus; angka utuh', () {
    final b = susunStruk(
      tx: tx(),
      items: [
        item('Nasi Goreng Spesial Telur Mata Sapi Pedas Level Lima', 2, 12000,
            'tanpa bawang goreng, telurnya setengah matang'),
      ],
      namaKasir: 'kasir dengan nama yang sangat panjang sekali',
    );
    for (final x in b) {
      expect(x.teks.length, lessThanOrEqualTo(32), reason: x.teks);
    }
    final t = teks(b);
    expect(t, contains('2 x @12.000               24.000'));
    expect(t[3], startsWith('Kasir    : '));
    expect(t[4], startsWith('           '), reason: 'lanjutan sejajar isi');
  });

  test('kertas 58 mm saja: 384 titik, 32 huruf, huruf kecil 42', () {
    expect((titikKertas, kolomNota, kolomKecil), (384, 32, 42));
  });

  test('test print: tanpa judul TEST PRINT dan tanpa kalimat penjelas', () {
    final t = teks(susunTestPrint(namaPrinter: 'RPP02N', waktu: waktu));
    expect(t, [
      'Jl. Kemiri Candi',
      '087859665084',
      '-' * 32,
      'Printer                   RPP02N',
      'Waktu           2026-11-01 00:49',
      '-' * 32,
    ]);
  });

  test('ESC/POS: logo di depan, huruf kecil = Font B, non-ASCII diganti', () {
    final b = keEscPos(
      const [BarisCetak('Café – x'), BarisCetak('kecil', kecil: true)],
      logo: const [0x1D, 0x76, 0x30, 0x00],
    );
    expect(b.sublist(0, 9),
        [0x1B, 0x40, 0x1B, 0x4A, 32, 0x1D, 0x76, 0x30, 0x00],
        reason: 'jarak ±4 mm lalu logo — TANPA rata tengah printer (RPP02N '
            'menaruh ujung kiri gambar di tengah)');
    final s = String.fromCharCodes(b);
    expect(s, contains('Cafe - x\n'));
    expect(s, contains('${String.fromCharCodes([0x1B, 0x4D, 1])}kecil\n'));
    expect(b.sublist(b.length - 3), [0x1B, 0x64, 4]);
    expect(b.every((x) => x < 0x80), isTrue);
  });

  test('logo: tepi kosong dipotong, diperkecil, ditengahkan aplikasi '
      'selebar kertas', () {
    // Gambar 20×10: kotak hitam 10×10 di kanan, kiri transparan.
    final rgba = Uint8List(20 * 10 * 4);
    for (var y = 0; y < 10; y++) {
      for (var x = 10; x < 20; x++) {
        rgba[(y * 20 + x) * 4 + 3] = 255; // hitam penuh
      }
    }
    final r = rasterLogo(rgba, 20, 10, lebarLogo: 8);
    expect(r.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 25, 0, 8, 0],
        reason: 'gambar berakhir di ujung kanan logo: 25 byte per baris, '
            'bukan 48 — data lebih sedikit, tinggi 8');
    expect(r.length, 8 + 25 * 8);
    final baris0 = r.sublist(8, 8 + 25);
    // Logo 8 titik di tengah 384: titik 188..195 → byte 23 (4 bit kanan) &
    // byte 24 (4 bit kiri).
    expect((baris0[23], baris0[24]), (0x0F, 0xF0));
    expect(baris0.where((x) => x != 0).length, 2);

    // Koreksi geser: -4 titik → 184..191 = byte 23 penuh.
    final g = rasterLogo(rgba, 20, 10, lebarLogo: 8, geser: -4);
    expect(g.sublist(8, 8 + 24)[23], 0xFF);
  });

  test('bungkus kata', () {
    expect(bungkus('a' * 40, 32), ['a' * 32, 'a' * 8]);
    expect(bungkus('', 32), ['']);
  });
}
