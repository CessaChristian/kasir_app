import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../features/sales/repositories/sales_repository.dart';
import '../../utils/currency_formatter.dart';
import '../constants/app_constants.dart';
import '../ui/header_teras.dart';
import '../ui/pegang_lembar.dart';
import '../ui/teks_teras.dart';
import '../ui/warna_teras.dart';
import 'business_logo.dart';

/// Detail transaksi berbentuk STRUK (desain): logo, info, item, total,
/// pembayaran — lalu "Cetak ulang struk" dan (kalau boleh) "Batalkan
/// transaksi".
///
/// Dipakai Riwayat, Laporan, dan Detail Shift. Transaksi yang dibatalkan
/// tetap menampilkan isinya sebagai bukti; keterangan pembatalannya tampil
/// di baris daftarnya, bukan di sini (desain).
class TransactionDetailSheet extends StatefulWidget {
  final Transaction transaction;

  /// Null = tombol "Batalkan transaksi" tidak tampil (tidak berhak, sudah
  /// batal, atau dibuka dari halaman yang memang tidak membatalkan).
  final VoidCallback? onBatalkan;

  /// Diisi test; aplikasi memakai basis data utama.
  final SalesRepository? repo;

  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    this.onBatalkan,
    this.repo,
  });

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late final _salesRepo = widget.repo ?? SalesRepository(db);
  List<TransactionItem>? _items;
  String? _namaKasir;

  /// Bayangan di bawah judul (struk sudah digulir) dan di atas tombol (masih
  /// ada struk di bawah). Yang bawah sekaligus petunjuk bahwa struk bisa
  /// digulir, langsung saat lembar dibuka.
  bool _bayanganAtas = false;
  bool _bayanganBawah = false;

  bool _perbaruiBayangan(ScrollMetrics m) {
    // Ambang 2px, sama dengan header halaman lain.
    final atas = m.pixels > 2;
    final bawah = m.extentAfter > 2;
    if (atas != _bayanganAtas || bawah != _bayanganBawah) {
      setState(() {
        _bayanganAtas = atas;
        _bayanganBawah = bawah;
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final tx = widget.transaction;
    // Struk yang dibatalkan tetap menampilkan isinya sebagai bukti.
    final items = await _salesRepo.getTransactionItems(
      tx.id,
      termasukBatal: tx.deletedAt != null,
    );
    final nama = await _salesRepo.namaAkun();
    if (mounted) {
      setState(() {
        _items = items;
        _namaKasir = nama[tx.cashierUserId];
      });
    }
  }

  static String _tipePesanan(String kode) => switch (kode) {
        'delivery' => 'Delivery',
        _ => 'Dine In',
      };

  // Tinggi dibatasi dari ruang yang BENAR-BENAR tersedia untuk lembar (di
  // bawah status bar), bukan dari tinggi layar: dulu "layar − 56" habis
  // dimakan status bar, lembarnya sampai ke lubang kamera dan tidak tersisa
  // area gelap untuk diketuk menutup. Isi yang lebih panjang digulir.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, batas) => _lembar(batas.maxHeight * _tinggiMaks),
  );

  /// Bagian ruang di bawah status bar yang boleh dipakai lembar; sisanya
  /// area gelap untuk diketuk menutup.
  static const _tinggiMaks = 0.85;

  Widget _lembar(double tinggiMaks) {
    final tx = widget.transaction;
    final tunai = tx.paymentMethod == 'cash';
    final dibayar = tunai ? (tx.cashReceived ?? tx.total) : tx.total;

    return Container(
      constraints: BoxConstraints(maxHeight: tinggiMaks),
      decoration: const BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tetap di tempat: pegangan dan judul.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const PegangLembar(), _judul(tx)],
            ),
          ),
          // Hanya struk yang digulir.
          Flexible(
            child: Stack(
              children: [
                // ScrollMetricsNotification juga terkirim saat pertama
                // tampil dan saat isi struk selesai dimuat — bukan hanya
                // saat jari menggeser.
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: (n) => _perbaruiBayangan(n.metrics),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) => _perbaruiBayangan(n.metrics),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _struk(tx, tunai, dibayar),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: BayanganHeader(terlihat: _bayanganAtas),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: BayanganHeader(terlihat: _bayanganBawah, keAtas: true),
                ),
              ],
            ),
          ),
          // Tetap di tempat: tombol.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _tombol(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _struk(Transaction tx, bool tunai, int dibayar) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
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
          const _GarisPutus(),
          _baris('Tanggal', DateFormat('dd/MM/yyyy').format(tx.createdAt)),
          _baris('Waktu', DateFormat('HH:mm:ss').format(tx.createdAt)),
          _baris('Kasir', _namaKasir ?? '-'),
          _baris('Tipe Pesanan', _tipePesanan(tx.orderType)),
          _baris('No. Transaksi', tx.invoiceNo),
          const _GarisPutus(),
          ..._daftarItem(),
          const _GarisPutus(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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
          _baris(
            'Dibayar (${tunai ? 'Cash' : 'QRIS'})',
            formatRp(dibayar),
          ),
          if (tunai)
            _baris(
              'Kembalian',
              formatRp(tx.change ?? (dibayar - tx.total)),
              warnaNilai: WarnaTeras.hijau,
            ),
          const _GarisPutus(),
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

  List<Widget> _tombol() => [
    SizedBox(
      height: 44,
      child: FilledButton.icon(
        // Fitur printer belum dibuat. Tombolnya tetap tampil supaya
        // sesuai desain, tapi belum melakukan apa-apa (keputusan
        // owner 2026-10-04) — tanpa pesan.
        onPressed: () {},
        style: FilledButton.styleFrom(
          backgroundColor: WarnaTeras.oranye,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        icon: const Icon(Icons.print_rounded, size: 19),
        label: const Text(
          'Cetak ulang struk',
          style: TextStyle(
            fontSize: TeksTeras.biasa,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    if (widget.onBatalkan != null) ...[
      const SizedBox(height: 8),
      SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: widget.onBatalkan,
          style: OutlinedButton.styleFrom(
            foregroundColor: WarnaTeras.merah,
            side: const BorderSide(color: Color(0xFFE0828A)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
          label: const Text(
            'Batalkan transaksi',
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  ];

  Widget _judul(Transaction tx) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: WarnaTeras.oranye,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detail Transaksi',
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                color: WarnaTeras.teks,
              ),
            ),
            Text(
              // Nomor nota, bukan tx.id — id adalah UUID internal.
              tx.invoiceNo,
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                color: WarnaTeras.teksSamar,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _baris(String kunci, String nilai, {Color? warnaNilai}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kunci,
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                color: WarnaTeras.teksSamar,
              ),
            ),
          ),
          Text(
            nilai,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              color: warnaNilai ?? WarnaTeras.teks,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _daftarItem() {
    final items = _items;
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
class _GarisPutus extends StatelessWidget {
  const _GarisPutus();

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
