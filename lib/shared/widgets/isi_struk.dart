import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../utils/currency_formatter.dart';
import '../constants/app_constants.dart';
import '../ui/teks_teras.dart';
import '../ui/warna_teras.dart';
import 'business_logo.dart';

/// Isi STRUK (desain): logo, info transaksi, item beserta pilihannya,
/// total, pembayaran, ucapan. Dipakai lembar Detail Transaksi dan struk
/// sesudah bayar di halaman Kasir — satu tampilan untuk keduanya.
class IsiStruk extends StatelessWidget {
  final Transaction transaksi;

  /// Null = masih dimuat.
  final List<TransactionItem>? items;
  final String? namaKasir;

  /// Detail Transaksi memakai abu muda; struk sesudah bayar putih.
  final Color latar;

  const IsiStruk({
    super.key,
    required this.transaksi,
    required this.items,
    required this.namaKasir,
    this.latar = const Color(0xFFF5F5F5),
  });

  static String _tipePesanan(String kode) => switch (kode) {
    'delivery' => 'Delivery',
    _ => 'Dine In',
  };

  @override
  Widget build(BuildContext context) {
    final tx = transaksi;
    final tunai = tx.paymentMethod == 'cash';
    final dibayar = tunai ? (tx.cashReceived ?? tx.total) : tx.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BusinessLogo(size: 52)),
          const SizedBox(height: 8),
          Text(
            AppConstants.storeName.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TeksTeras.judulBagian,
              fontWeight: FontWeight.w800,
              color: WarnaTeras.teks,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '${AppConstants.storeName} ${AppConstants.storeAddress}\n'
            '${AppConstants.storePhone}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              color: Color(0xFFB5ADA6),
            ),
          ),
          const GarisPutus(),
          _baris('Tanggal', DateFormat('dd/MM/yyyy').format(tx.createdAt)),
          _baris('Waktu', DateFormat('HH:mm:ss').format(tx.createdAt)),
          _baris('Kasir', namaKasir ?? '-'),
          _baris('Tipe Pesanan', _tipePesanan(tx.orderType)),
          // Nama open bill; penjualan langsung tidak punya nama pelanggan.
          if (tx.billName case final nama? when nama.isNotEmpty)
            _baris('Pelanggan', nama),
          _baris('No. Transaksi', tx.invoiceNo),
          const GarisPutus(),
          ..._daftarItem(),
          const GarisPutus(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: WarnaTeras.latar,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatRp(tx.total),
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.oranye,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _baris('Dibayar (${tunai ? 'Cash' : 'QRIS'})', formatRp(dibayar)),
          if (tunai)
            _baris(
              'Kembalian',
              formatRp(tx.change ?? (dibayar - tx.total)),
              warnaNilai: WarnaTeras.hijau,
            ),
          const GarisPutus(),
          const Text(
            'Terima Kasih!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Selamat Menikmati',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              color: WarnaTeras.teksSamar,
            ),
          ),
        ],
      ),
    );
  }

  Widget _baris(String kunci, String nilai, {Color? warnaNilai}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kunci,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.teksSamar,
            ),
          ),
          const SizedBox(width: 12),
          // Nilai panjang (nomor nota) turun baris di layar sempit, bukan
          // tumpah ke samping.
          Expanded(
            child: Text(
              nilai,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: TeksTeras.kecil,
                color: warnaNilai ?? WarnaTeras.teks,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _daftarItem() {
    final items = this.items;
    if (items == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    if (items.isEmpty) {
      return const [
        Text(
          'Tidak ada item',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: TeksTeras.kecil,
            color: WarnaTeras.teksSamar,
          ),
        ),
      ];
    }
    return [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(fontSize: TeksTeras.kecil),
              ),
              if (item.notes != null && item.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '**${item.notes}',
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.merah,
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.qty} x ${formatRp(item.priceAtSale)}',
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksSamar,
                      ),
                    ),
                  ),
                  Text(
                    formatRupiah(item.subtotal),
                    style: const TextStyle(fontSize: TeksTeras.kecil),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }
}

/// Garis putus-putus pemisah bagian struk.
class GarisPutus extends StatelessWidget {
  const GarisPutus({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final jumlah = (c.maxWidth / 7).floor();
          return Row(
            children: [
              for (var i = 0; i < jumlah; i++)
                Container(
                  width: 4,
                  height: 1,
                  margin: const EdgeInsets.only(right: 3),
                  color: const Color(0xFFC9C3BD),
                ),
            ],
          );
        },
      ),
    );
  }
}
