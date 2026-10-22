import 'dart:convert';

import '../../../data/app_database.dart';
import '../../../data/models/sale_line.dart';

/// Satu baris pesanan di open bill: produk, jumlah, dan catatan varian.
/// Nama dan harga SENGAJA tidak disimpan — diambil dari produk terbaru saat
/// bill dibuka (keputusan owner 2026-10-14).
typedef BarisBill = ({String idProduk, int jumlah, String? catatan});

/// Isi keranjang → teks JSON untuk kolom `open_bills.items`.
String kodekanIsiBill(List<SaleLine> baris) => kodekanBarisBill([
  for (final b in baris)
    (idProduk: b.productId, jumlah: b.qty, catatan: b.notes),
]);

/// [BarisBill] → teks JSON untuk kolom `open_bills.items`.
String kodekanBarisBill(List<BarisBill> baris) => jsonEncode([
  for (final b in baris)
    {'p': b.idProduk, 'q': b.jumlah, if (b.catatan != null) 'c': b.catatan},
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

/// Dua isi bill sama persis jumlahnya per baris (urutan tidak dihitung).
bool isiBillSama(String a, String b) {
  final x = _jumlahPerBaris(bacaIsiBill(a));
  final y = _jumlahPerBaris(bacaIsiBill(b));
  return x.length == y.length && x.entries.every((e) => y[e.key] == e.value);
}

/// Gabungkan perubahan HP ini ke isi bill terbaru: [terkini] (isi bill di
/// server, sudah memuat perubahan HP lain) + selisih [awal] → [milikku]
/// (yang diubah kasir di HP ini sejak bill dimuat ke keranjang).
///
/// Contoh: awal Latte×1; HP lain menambah Latte → terkini Latte×2; HP ini
/// menambah Teh → milikku Latte×1 + Teh×1. Hasil: Latte×2 + Teh×1 — tidak
/// ada tambahan yang hilang. Jumlah yang habis (≤0) dibuang.
///
/// Baris dianggap sama kalau produk DAN catatannya (pilihan + catatan)
/// sama, seperti di keranjang. Urutan mengikuti [terkini], baris baru
/// menyusul sesuai urutan [milikku].
List<BarisBill> gabungIsiBill({
  required List<BarisBill> awal,
  required List<BarisBill> milikku,
  required List<BarisBill> terkini,
}) {
  final hasil = _jumlahPerBaris(terkini);
  final sebelum = _jumlahPerBaris(awal);
  final sesudah = _jumlahPerBaris(milikku);
  for (final kunci in {...sebelum.keys, ...sesudah.keys}) {
    final selisih = (sesudah[kunci] ?? 0) - (sebelum[kunci] ?? 0);
    if (selisih != 0) hasil[kunci] = (hasil[kunci] ?? 0) + selisih;
  }
  return [
    for (final MapEntry(key: (idProduk, catatan), value: jumlah)
        in hasil.entries)
      if (jumlah > 0)
        (idProduk: idProduk, jumlah: jumlah, catatan: catatan),
  ];
}

/// Jumlah per (produk, catatan), urut kemunculan pertama.
Map<(String, String?), int> _jumlahPerBaris(List<BarisBill> baris) {
  final m = <(String, String?), int>{};
  for (final b in baris) {
    final kunci = (b.idProduk, b.catatan);
    m[kunci] = (m[kunci] ?? 0) + b.jumlah;
  }
  return m;
}

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
BillTermuat muatBill(OpenBill bill, Iterable<Product> produk) =>
    muatIsiBill(bill.items, produk);

/// Seperti [muatBill], untuk isi bill [isi] (JSON `open_bills.items`).
BillTermuat muatIsiBill(String isi, Iterable<Product> produk) {
  final perId = {for (final p in produk) p.id: p};
  final baris = <SaleLine>[];
  var hilang = 0;
  for (final b in bacaIsiBill(isi)) {
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
