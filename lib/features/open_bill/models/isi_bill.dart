import 'dart:convert';

import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';

/// Satu baris pesanan di open bill: produk, jumlah, dan catatan varian.
/// Nama dan harga SENGAJA tidak disimpan — diambil dari produk terbaru saat
/// bill dibuka (keputusan owner 2026-10-14).
typedef BarisBill = ({String idProduk, int jumlah, String? catatan});

/// Isi keranjang → teks JSON untuk kolom `open_bills.items`.
String kodekanIsiBill(List<SaleLine> baris) => jsonEncode([
  for (final b in baris)
    {'p': b.productId, 'q': b.qty, if (b.notes != null) 'c': b.notes},
]);

/// Kebalikan [kodekanIsiBill].
List<BarisBill> bacaIsiBill(String json) => [
  for (final m in (jsonDecode(json) as List).cast<Map<String, dynamic>>())
    (
      idProduk: m['p'] as String,
      jumlah: (m['q'] as num).toInt(),
      catatan: m['c'] as String?,
    ),
];

/// Isi bill yang siap dimasukkan ke keranjang.
class BillTermuat {
  /// Baris dengan nama dan harga produk TERBARU.
  final List<SaleLine> baris;

  /// Berapa produk yang dibuang karena sudah dihapus owner.
  final int produkHilang;

  const BillTermuat(this.baris, this.produkHilang);

  int get total => baris.fold(0, (s, b) => s + b.subtotal);
  int get jumlahItem => baris.fold(0, (s, b) => s + b.qty);
}

/// Muat [bill] memakai daftar [produk] yang masih dijual. Produk yang sudah
/// tidak ada dibuang dan dihitung di [BillTermuat.produkHilang].
BillTermuat muatBill(OpenBill bill, Iterable<Product> produk) {
  final perId = {for (final p in produk) p.id: p};
  final baris = <SaleLine>[];
  var hilang = 0;
  for (final b in bacaIsiBill(bill.items)) {
    final p = perId[b.idProduk];
    if (p == null) {
      hilang++;
      continue;
    }
    baris.add(
      SaleLine(
        productId: p.id,
        productName: p.name,
        qty: b.jumlah,
        priceAtSale: p.price,
        notes: b.catatan,
      ),
    );
  }
  return BillTermuat(baris, hilang);
}
