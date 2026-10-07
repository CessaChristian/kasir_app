import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';

import '../../../shared/ui/periode/periode.dart';
import '../../expenses/models/kategori_biaya.dart';
import '../models/ringkasan_laporan.dart';

/// Isi satu sel tabel laporan. Excel menulis [SelRupiah] dan [SelAngka]
/// sebagai ANGKA (bisa dijumlah), PDF menulisnya sebagai teks berformat.
sealed class Sel {
  const Sel();
}

class SelTeks extends Sel {
  final String teks;
  const SelTeks(this.teks);
}

class SelAngka extends Sel {
  final int nilai;
  const SelAngka(this.nilai);
}

class SelRupiah extends Sel {
  final int nilai;
  const SelRupiah(this.nilai);
}

/// Satu bagian laporan: lembar di Excel, tabel bertajuk di PDF.
class TabelLaporan {
  final String judul;
  final List<String> kolom;
  final List<List<Sel>> baris;

  /// Lebar relatif tiap kolom (PDF) / lebar karakter (Excel).
  final List<double> lebar;

  /// Indeks baris yang ditulis tebal berlatar, mis. total per bulan.
  final Set<int> barisTebal;

  const TabelLaporan({
    required this.judul,
    required this.kolom,
    required this.baris,
    required this.lebar,
    this.barisTebal = const {},
  });
}

/// Seluruh isi file unduhan Laporan — dipakai bersama oleh Excel dan PDF,
/// supaya isinya selalu sama.
class DokumenLaporan {
  final String namaToko;
  final Periode periode;
  final DateTime dibuat;
  final String olehNama;
  final List<TabelLaporan> tabel;

  const DokumenLaporan({
    required this.namaToko,
    required this.periode,
    required this.dibuat,
    required this.olehNama,
    required this.tabel,
  });

  /// "01/10/2026" atau "01/10/2026 – 05/10/2026" (desain).
  String get labelPeriode => labelPeriodeUnduhan(periode);

  /// "Laporan_01102026" atau "Laporan_01102026-05102026" (tanpa ekstensi).
  String get namaFile {
    final f = DateFormat('ddMMyyyy');
    return periode.satuHari
        ? 'Laporan_${f.format(periode.dari)}'
        : 'Laporan_${f.format(periode.dari)}-${f.format(periode.sampai)}';
  }
}

String labelPeriodeUnduhan(Periode p) {
  final f = DateFormat('dd/MM/yyyy');
  return p.satuHari
      ? f.format(p.dari)
      : '${f.format(p.dari)} – ${f.format(p.sampai)}';
}

/// Susun 8 bagian laporan dari [r] (hitungan yang sama dengan layar).
///
/// [denganPengeluaran] false untuk akun yang tidak boleh melihat
/// pengeluaran: kolom/baris/lembar pengeluaran tidak ikut. [nama]: nama akun
/// per id, untuk kasir dan pembatal.
DokumenLaporan susunDokumenLaporan({
  required String namaToko,
  required Periode periode,
  required RingkasanLaporan r,
  required Map<String, String> nama,
  required bool denganPengeluaran,
  required DateTime dibuat,
  required String olehNama,
}) {
  String atauStrip(String? n) => n ?? '-';
  final tanggal = DateFormat('dd/MM/yyyy');
  final jam = DateFormat('HH:mm');
  int persen(int nilai, int total) =>
      total == 0 ? 0 : (nilai / total * 100).round();

  // 1. Ringkasan
  final ringkasan = TabelLaporan(
    judul: 'Ringkasan',
    kolom: const ['Keterangan', 'Jumlah', 'Nilai'],
    lebar: const [28, 12, 18],
    baris: [
      [const SelTeks('Pendapatan'), const SelTeks(''), SelRupiah(r.pendapatan)],
      [
        const SelTeks('Transaksi'),
        SelAngka(r.jumlahTransaksi),
        const SelTeks(''),
      ],
      [
        const SelTeks('Rata-rata / transaksi'),
        const SelTeks(''),
        SelRupiah(r.rataRata),
      ],
      if (denganPengeluaran) ...[
        [
          const SelTeks('Pengeluaran'),
          SelAngka(r.pengeluaranSah.length),
          SelRupiah(r.pengeluaran),
        ],
        [
          const SelTeks('Laba kotor'),
          const SelTeks(''),
          SelRupiah(r.labaKotor),
        ],
      ],
      [const SelTeks('Shift'), SelAngka(r.jumlahShift), const SelTeks('')],
      [
        const SelTeks('Tunai'),
        SelAngka(r.tunai.jumlah),
        SelRupiah(r.tunai.nilai),
      ],
      [const SelTeks('QRIS'), SelAngka(r.qris.jumlah), SelRupiah(r.qris.nilai)],
      [
        const SelTeks('Dine In'),
        SelAngka(r.dineIn.jumlah),
        SelRupiah(r.dineIn.nilai),
      ],
      [
        const SelTeks('Delivery'),
        SelAngka(r.delivery.jumlah),
        SelRupiah(r.delivery.nilai),
      ],
      [
        const SelTeks('Transaksi dibatalkan'),
        SelAngka(r.transaksiBatal.length),
        SelRupiah(r.nilaiTransaksiBatal),
      ],
      if (denganPengeluaran)
        [
          const SelTeks('Pengeluaran dibatalkan'),
          SelAngka(r.pengeluaranBatal.length),
          SelRupiah(r.nilaiPengeluaranBatal),
        ],
    ],
  );

  // 2. Per jam / per hari / per bulan (hanya yang ada isinya)
  final perWaktu = TabelLaporan(
    judul: periode.satuHari
        ? 'Per Jam'
        : r.jumlahHari <= 31
        ? 'Per Hari'
        : 'Per Bulan',
    barisTebal: {
      for (var i = 0; i < r.perWaktu.length; i++)
        if (r.perWaktu[i].totalBulan) i,
    },
    kolom: [
      periode.satuHari ? 'Jam' : 'Tanggal',
      'Transaksi',
      'Pendapatan',
      'Tunai',
      'QRIS',
      if (denganPengeluaran) ...['Pengeluaran', 'Laba kotor'],
    ],
    lebar: [
      periode.satuHari ? 14 : 26,
      10,
      15,
      15,
      15,
      if (denganPengeluaran) ...[15, 15],
    ],
    baris: [
      for (final w in r.perWaktu)
        [
          SelTeks(w.label),
          SelAngka(w.transaksi),
          SelRupiah(w.pendapatan),
          SelRupiah(w.tunai),
          SelRupiah(w.qris),
          if (denganPengeluaran) ...[
            SelRupiah(w.pengeluaran),
            SelRupiah(w.labaKotor),
          ],
        ],
    ],
  );

  // 3. Produk (yang terjual, pendapatan terbesar dulu)
  final laku = r.perProduk.where((p) => p.terjual > 0).toList()
    ..sort((a, b) {
      final c = b.nilai.compareTo(a.nilai);
      return c != 0 ? c : a.nama.compareTo(b.nama);
    });
  final produk = TabelLaporan(
    judul: 'Produk',
    kolom: const ['No', 'Produk', 'Kategori', 'Terjual', 'Pendapatan', '%'],
    lebar: const [5, 26, 18, 9, 15, 6],
    baris: [
      for (var i = 0; i < laku.length; i++)
        [
          SelAngka(i + 1),
          SelTeks(laku[i].nama),
          SelTeks(laku[i].kategori),
          SelAngka(laku[i].terjual),
          SelRupiah(laku[i].nilai),
          SelAngka(persen(laku[i].nilai, r.pendapatan)),
        ],
    ],
  );

  // 4. Kategori
  final terjualPerKategori = <String, int>{};
  for (final p in r.perProduk) {
    terjualPerKategori[p.kategori] =
        (terjualPerKategori[p.kategori] ?? 0) + p.terjual;
  }
  final kategori = TabelLaporan(
    judul: 'Kategori',
    kolom: const ['Kategori', 'Terjual', 'Pendapatan', '%'],
    lebar: const [24, 10, 15, 6],
    baris: [
      for (final k in r.perKategori)
        [
          SelTeks(k.nama),
          SelAngka(terjualPerKategori[k.nama] ?? 0),
          SelRupiah(k.nilai),
          SelAngka(persen(k.nilai, r.pendapatan)),
        ],
    ],
  );

  // 5 & 6. Transaksi dan rincian item (sah, lama ke baru), dikelompokkan
  // menurut panjang periode — lihat [kelompokkanTransaksi].
  final kelompok = kelompokkanTransaksi(periode, r.transaksi.reversed);

  final barisTransaksi = <List<Sel>>[];
  final tebalTransaksi = <int>{};
  final barisItem = <List<Sel>>[];
  final tebalItem = <int>{};
  for (final k in kelompok) {
    final isiItem = [
      for (final t in k.transaksi)
        for (final i in r.item[t.id] ?? const <TransactionItem>[]) (t, i),
    ];
    if (k.judul != null) {
      tebalTransaksi.add(barisTransaksi.length);
      barisTransaksi.add([
        SelTeks(k.judul!),
        const SelTeks(''),
        const SelTeks(''),
        SelTeks('${k.transaksi.length} transaksi'),
        const SelTeks(''),
        const SelTeks(''),
        SelRupiah(k.transaksi.fold(0, (s, t) => s + t.total)),
      ]);
      tebalItem.add(barisItem.length);
      barisItem.add([
        SelTeks(k.judul!),
        const SelTeks(''),
        const SelTeks(''),
        const SelTeks(''),
        SelAngka(isiItem.fold(0, (s, x) => s + x.$2.qty)),
        const SelTeks(''),
        SelRupiah(isiItem.fold(0, (s, x) => s + x.$2.subtotal)),
      ]);
    }
    for (final t in k.transaksi) {
      barisTransaksi.add([
        SelTeks(t.invoiceNo),
        SelTeks(tanggal.format(t.createdAt.toLocal())),
        SelTeks(jam.format(t.createdAt.toLocal())),
        SelTeks(atauStrip(t.namaKasir(nama))),
        SelTeks(t.orderType == 'delivery' ? 'Delivery' : 'Dine In'),
        SelTeks(t.paymentMethod == 'qris' ? 'QRIS' : 'Tunai'),
        SelRupiah(t.total),
      ]);
    }
    for (final (t, i) in isiItem) {
      barisItem.add([
        SelTeks(t.invoiceNo),
        SelTeks(tanggal.format(t.createdAt.toLocal())),
        SelTeks(i.productName),
        SelTeks(i.notes ?? ''),
        SelAngka(i.qty),
        SelRupiah(i.priceAtSale),
        SelRupiah(i.subtotal),
      ]);
    }
  }

  final transaksi = TabelLaporan(
    judul: 'Transaksi',
    kolom: const [
      'No. Nota',
      'Tanggal',
      'Jam',
      'Kasir',
      'Tipe',
      'Metode',
      'Total',
    ],
    lebar: const [24, 11, 7, 12, 9, 8, 13],
    baris: barisTransaksi,
    barisTebal: tebalTransaksi,
  );

  final item = TabelLaporan(
    judul: 'Rincian Item',
    kolom: const [
      'No. Nota',
      'Tanggal',
      'Produk',
      'Catatan',
      'Qty',
      'Harga',
      'Subtotal',
    ],
    lebar: const [24, 11, 20, 18, 5, 12, 13],
    baris: barisItem,
    barisTebal: tebalItem,
  );

  // 7. Pengeluaran (sah, lama ke baru)
  final pengeluaran = TabelLaporan(
    judul: 'Pengeluaran',
    kolom: const [
      'Tanggal',
      'Jam',
      'Keterangan',
      'Kategori Biaya',
      'Qty',
      'Nominal',
      'Dicatat oleh',
    ],
    lebar: const [11, 7, 24, 16, 5, 13, 13],
    baris: [
      for (final e in r.pengeluaranSah.reversed)
        [
          SelTeks(tanggal.format(e.createdAt.toLocal())),
          SelTeks(jam.format(e.createdAt.toLocal())),
          SelTeks(e.description),
          SelTeks(KategoriBiaya.labelDari(e.category)),
          SelAngka(e.qty),
          SelRupiah(e.amount),
          SelTeks(atauStrip(e.namaPencatat(nama))),
        ],
    ],
  );

  // 8. Dibatalkan
  final dibatalkan = TabelLaporan(
    judul: 'Dibatalkan',
    kolom: const [
      'Jenis',
      'Nota / Keterangan',
      'Tanggal',
      'Nilai',
      'Dibatalkan oleh',
      'Waktu batal',
      'Alasan',
    ],
    lebar: const [11, 24, 11, 13, 13, 15, 24],
    baris: [
      for (final t in r.transaksiBatal.reversed)
        [
          const SelTeks('Transaksi'),
          SelTeks(t.invoiceNo),
          SelTeks(tanggal.format(t.createdAt.toLocal())),
          SelRupiah(t.total),
          SelTeks(atauStrip(t.namaPembatal(nama))),
          SelTeks(_waktu(t.deletedAt!)),
          SelTeks(t.cancelReason ?? 'tidak tercatat'),
        ],
      if (denganPengeluaran)
        for (final e in r.pengeluaranBatal.reversed)
          [
            const SelTeks('Pengeluaran'),
            SelTeks(e.qty > 1 ? '${e.description} (${e.qty}x)' : e.description),
            SelTeks(tanggal.format(e.createdAt.toLocal())),
            SelRupiah(e.amount),
            SelTeks(atauStrip(e.namaPembatal(nama))),
            SelTeks(_waktu(e.deletedAt!)),
            SelTeks(e.cancelReason ?? 'tidak tercatat'),
          ],
    ],
  );

  return DokumenLaporan(
    namaToko: namaToko,
    periode: periode,
    dibuat: dibuat,
    olehNama: olehNama,
    tabel: [
      ringkasan,
      perWaktu,
      produk,
      kategori,
      transaksi,
      item,
      if (denganPengeluaran) pengeluaran,
      dibatalkan,
    ],
  );
}

/// Satu kelompok di lembar Transaksi/Rincian Item. [judul] null = tanpa
/// kelompok (periode satu hari).
class KelompokTransaksi {
  final String? judul;
  final List<Transaction> transaksi;

  const KelompokTransaksi(this.judul, this.transaksi);
}

/// Kelompok Transaksi dan Rincian Item menurut panjang periode (keputusan
/// owner 2026-10-06), supaya tiap kelompok tetap enak dibaca:
/// - 1 hari: tanpa kelompok;
/// - 2–7 hari: per hari;
/// - 8–31 hari: per minggu — blok 7 hari dari awal periode (1–7, 8–14, …,
///   29–31), bukan Senin–Minggu, supaya tidak terpotong aneh di awal bulan;
/// - lebih dari 31 hari: per bulan.
///
/// Kelompok tanpa transaksi tidak dibuat. [urut]: lama ke baru.
List<KelompokTransaksi> kelompokkanTransaksi(
  Periode periode,
  Iterable<Transaction> urut,
) {
  final daftar = urut.toList();
  final jumlahHari = periode.sampai.difference(periode.dari).inDays + 1;
  if (jumlahHari == 1) return [KelompokTransaksi(null, daftar)];

  final hari = DateFormat('EEEE, d MMM yyyy', 'id_ID');
  final bulan = DateFormat('MMMM yyyy', 'id_ID');
  final kunci = <String, (String, List<Transaction>)>{};
  for (final t in daftar) {
    final w = t.createdAt.toLocal();
    final tgl = DateTime(w.year, w.month, w.day);
    final String id;
    final String judul;
    if (jumlahHari <= 7) {
      id = '$tgl';
      judul = hari.format(tgl);
    } else if (jumlahHari <= 31) {
      final ke = tgl.difference(periode.dari).inDays ~/ 7;
      final awal = DateTime(
        periode.dari.year,
        periode.dari.month,
        periode.dari.day + ke * 7,
      );
      final akhirMinggu = DateTime(awal.year, awal.month, awal.day + 6);
      final akhir = akhirMinggu.isAfter(periode.sampai)
          ? periode.sampai
          : akhirMinggu;
      id = 'm$ke';
      judul = 'Minggu ${ke + 1} · ${_rentangTanggal(awal, akhir)}';
    } else {
      id = '${w.year}-${w.month}';
      judul = bulan.format(tgl);
    }
    kunci.putIfAbsent(id, () => (judul, [])).$2.add(t);
  }
  return [
    for (final (judul, isi) in kunci.values) KelompokTransaksi(judul, isi),
  ];
}

/// "1–7 Jul 2026" atau "29 Jun – 5 Jul 2026".
String _rentangTanggal(DateTime a, DateTime b) {
  final bulanTahun = DateFormat('MMM yyyy', 'id_ID');
  if (a.year == b.year && a.month == b.month) {
    return a.day == b.day
        ? '${a.day} ${bulanTahun.format(a)}'
        : '${a.day}–${b.day} ${bulanTahun.format(a)}';
  }
  return '${DateFormat('d MMM', 'id_ID').format(a)} – '
      '${b.day} ${bulanTahun.format(b)}';
}

String _waktu(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
