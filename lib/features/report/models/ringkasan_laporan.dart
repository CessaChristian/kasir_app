import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/periode/periode.dart';

/// Satu batang di grafik Tren Pendapatan. [label] kosong = batang tanpa
/// tulisan (desain menulis label selang-seling supaya tidak berdesakan).
/// [nama] tampil di gelembung saat batangnya diketuk: "Jam 08:00",
/// "Sen, 1 Okt", atau "Okt 2026".
class BatangGrafik {
  final String label;
  final String nama;
  final int nilai;

  const BatangGrafik(this.label, this.nilai, {required this.nama});
}

/// Satu baris rincian per waktu untuk file unduhan: per jam (periode satu
/// hari), per hari, atau — periode lebih dari 31 hari — baris total bulan
/// ([totalBulan]) diikuti hari-harinya.
class BarisWaktu {
  final String label;

  /// Baris total satu bulan (ditulis tebal); selain itu baris jam/hari.
  final bool totalBulan;
  final int transaksi;
  final int pendapatan;
  final int tunai;
  final int qris;
  final int pengeluaran;

  const BarisWaktu({
    required this.label,
    required this.transaksi,
    required this.pendapatan,
    required this.tunai,
    required this.qris,
    required this.pengeluaran,
    this.totalBulan = false,
  });

  int get labaKotor => pendapatan - pengeluaran;

  /// Tidak ada transaksi maupun pengeluaran — tidak dimasukkan ke laporan.
  bool get kosong => transaksi == 0 && pengeluaran == 0;
}

/// Jumlah transaksi dan nominalnya, mis. untuk Tunai atau Delivery.
class Porsi {
  final int jumlah;
  final int nilai;

  const Porsi(this.jumlah, this.nilai);
}

class PendapatanKategori {
  final String nama;

  /// Codepoint ikon kategori; null = kategori belum punya ikon.
  final int? ikon;
  final int nilai;

  /// Baris produk tanpa kategori (bukan kategori sungguhan).
  final bool tanpaKategori;

  const PendapatanKategori(
    this.nama,
    this.ikon,
    this.nilai, {
    this.tanpaKategori = false,
  });
}

class PenjualanProduk {
  final String nama;
  final String? foto;
  final String kategori;
  final int terjual;
  final int nilai;

  /// Produk ini tidak punya kategori ([kategori] berisi "Tanpa Kategori").
  /// Ditandai terpisah, bukan dari namanya: kategori sungguhan yang dinamai
  /// "Tanpa Kategori" dulu tergabung dengannya dan kehilangan ikonnya
  /// (review D7).
  final bool tanpaKategori;

  const PenjualanProduk({
    required this.nama,
    required this.foto,
    required this.kategori,
    required this.terjual,
    required this.nilai,
    this.tanpaKategori = false,
  });

  /// False untuk produk tanpa kategori — di baris produk Laporan cukup
  /// "N terjual", tanpa tulisan kategori.
  bool get punyaKategori => !tanpaKategori;
}

/// Isi halaman Laporan untuk satu periode (desain). Semua angka hanya
/// menghitung yang sah; yang dibatalkan dikumpulkan terpisah.
class RingkasanLaporan {
  final int pendapatan;
  final int jumlahTransaksi;
  final int pengeluaran;
  final int jumlahShift;
  final int jumlahHari;

  /// Transaksi sah (terbaru dulu) beserta isinya — untuk ekspor Excel.
  final List<Transaction> transaksi;
  final Map<String, List<TransactionItem>> item;

  final List<Transaction> transaksiBatal;
  final List<Expense> pengeluaranBatal;

  /// Pengeluaran sah (terbaru dulu) — untuk file unduhan.
  final List<Expense> pengeluaranSah;

  /// Untuk file unduhan: per jam (periode satu hari), per hari (sampai 31
  /// hari), atau per bulan beserta harinya. Jam/hari/bulan tanpa transaksi
  /// dan tanpa pengeluaran tidak ikut.
  final List<BarisWaktu> perWaktu;

  final String judulGrafik;
  final List<BatangGrafik> grafik;

  /// Periode satu hari tanpa shift sama sekali: grafik per jam tidak punya
  /// rentang jam untuk digambar.
  final bool tanpaShift;

  final Porsi tunai;
  final Porsi qris;
  final Porsi dineIn;
  final Porsi delivery;

  /// Terbesar dulu.
  final List<PendapatanKategori> perKategori;

  /// Semua produk, termasuk yang tidak laku dan yang sudah dihapus tapi
  /// terjual di periode ini. Urutannya diatur halaman (Pendapatan/Terjual).
  final List<PenjualanProduk> perProduk;

  const RingkasanLaporan({
    required this.pendapatan,
    required this.jumlahTransaksi,
    required this.pengeluaran,
    required this.jumlahShift,
    required this.jumlahHari,
    required this.transaksi,
    required this.item,
    required this.transaksiBatal,
    required this.pengeluaranBatal,
    required this.pengeluaranSah,
    required this.perWaktu,
    required this.judulGrafik,
    required this.grafik,
    required this.tanpaShift,
    required this.tunai,
    required this.qris,
    required this.dineIn,
    required this.delivery,
    required this.perKategori,
    required this.perProduk,
  });

  int get rataRata =>
      jumlahTransaksi == 0 ? 0 : (pendapatan / jumlahTransaksi).round();
  int get labaKotor => pendapatan - pengeluaran;

  /// Ada yang bisa dilaporkan di file unduhan: transaksi (sah atau batal),
  /// atau — bagi yang boleh melihatnya — pengeluaran. Periode yang hanya
  /// berisi belanja tetap bisa diunduh.
  bool adaIsi({required bool denganPengeluaran}) =>
      transaksi.isNotEmpty ||
      transaksiBatal.isNotEmpty ||
      (denganPengeluaran &&
          (pengeluaranSah.isNotEmpty || pengeluaranBatal.isNotEmpty));

  int get nilaiTransaksiBatal => transaksiBatal.fold(0, (s, t) => s + t.total);
  int get nilaiPengeluaranBatal =>
      pengeluaranBatal.fold(0, (s, e) => s + e.amount);
}

const _namaHari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Hitung isi Laporan.
///
/// [transaksi] dan [pengeluaran]: semua yang tercatat di [periode], termasuk
/// yang dibatalkan. [item]: isi transaksi yang sah, per id transaksi.
/// [shift]: shift yang dimulai di [periode]. [produk] dan [kategori]: semua,
/// termasuk yang sudah dihapus — laporan membaca riwayat penjualan.
RingkasanLaporan ringkasLaporan({
  required Periode periode,
  required List<Transaction> transaksi,
  required Map<String, List<TransactionItem>> item,
  required List<Expense> pengeluaran,
  required List<Shift> shift,
  required List<Product> produk,
  required List<Category> kategori,
  required DateTime sekarang,
}) {
  final sah = transaksi.where((t) => t.deletedAt == null).toList();
  int jumlahkan(Iterable<Transaction> l) => l.fold(0, (s, t) => s + t.total);
  Porsi porsi(bool Function(Transaction) syarat) {
    final l = sah.where(syarat);
    return Porsi(l.length, jumlahkan(l));
  }

  final hari = [
    for (
      var d = periode.dari;
      !d.isAfter(periode.sampai);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];
  final (judul, grafik, tanpaShift) = _grafik(hari, sah, shift, sekarang);
  final pengeluaranSah = pengeluaran.where((e) => e.deletedAt == null).toList();
  final perProduk = _perProduk(sah, item, produk, kategori);

  return RingkasanLaporan(
    pendapatan: jumlahkan(sah),
    jumlahTransaksi: sah.length,
    pengeluaran: pengeluaranSah.fold(0, (s, e) => s + e.amount),
    jumlahShift: shift.length,
    jumlahHari: hari.length,
    transaksi: sah,
    item: item,
    transaksiBatal: transaksi.where((t) => t.deletedAt != null).toList(),
    pengeluaranBatal: pengeluaran.where((e) => e.deletedAt != null).toList(),
    pengeluaranSah: pengeluaranSah,
    perWaktu: _perWaktu(hari, sah, pengeluaranSah),
    judulGrafik: judul,
    grafik: grafik,
    tanpaShift: tanpaShift,
    tunai: porsi((t) => t.paymentMethod != 'qris'),
    qris: porsi((t) => t.paymentMethod == 'qris'),
    // Selain Delivery = Dine In (Take Away digabung, v34).
    dineIn: porsi((t) => t.orderType != 'delivery'),
    delivery: porsi((t) => t.orderType == 'delivery'),
    perKategori: _perKategori(perProduk, kategori),
    perProduk: perProduk,
  );
}

/// Grafik menurut panjang periode (desain): 1 hari per jam, sampai 31 hari
/// per hari, lebih dari itu per bulan.
(String, List<BatangGrafik>, bool) _grafik(
  List<DateTime> hari,
  List<Transaction> sah,
  List<Shift> shift,
  DateTime sekarang,
) {
  // Dijumlahkan sekali jalan per jam/hari/bulan. Dulu setiap batang menyisir
  // semua transaksi periode itu: setahun = 365 × semua transaksi (audit 6 Nov
  // nomor 56).
  final perJam = <int, int>{};
  final perHari = <int, int>{};
  final perBulan = <int, int>{};
  for (final t in sah) {
    final w = t.createdAt.toLocal();
    perJam[w.hour] = (perJam[w.hour] ?? 0) + t.total;
    final kh = _kunciHari(w);
    perHari[kh] = (perHari[kh] ?? 0) + t.total;
    final kb = _kunciBulan(w);
    perBulan[kb] = (perBulan[kb] ?? 0) + t.total;
  }

  if (hari.length == 1) {
    // Rentang jam mengikuti shift hari itu: dari shift pertama dibuka sampai
    // shift terakhir ditutup (yang masih berjalan: sampai sekarang).
    // Transaksi di luar rentang itu tetap ikut supaya tidak ada penjualan
    // yang hilang dari grafik.
    final rentang = _rentangJam(
      shift,
      sah.map((t) => t.createdAt),
      sekarang,
      hari: hari.single,
    );
    if (rentang == null) return ('Pendapatan per jam', const [], true);
    final (awal, akhir) = rentang;
    return (
      'Pendapatan per jam',
      [
        for (var h = awal; h <= akhir; h++)
          BatangGrafik(
            h.isOdd ? '' : h.toString().padLeft(2, '0'),
            perJam[h] ?? 0,
            nama: 'Jam ${h.toString().padLeft(2, '0')}:00',
          ),
      ],
      false,
    );
  }

  if (hari.length <= 31) {
    final langkah = hari.length > 14
        ? 5
        : hari.length > 7
        ? 2
        : 1;
    return (
      'Pendapatan per hari',
      [
        for (var i = 0; i < hari.length; i++)
          BatangGrafik(
            hari.length <= 7
                ? _namaHari[hari[i].weekday - 1]
                : (i % langkah == 0 ? '${hari[i].day}' : ''),
            perHari[_kunciHari(hari[i])] ?? 0,
            nama:
                '${_namaHari[hari[i].weekday - 1]}, ${hari[i].day} '
                '${DateFormat('MMM', 'id_ID').format(hari[i])}',
          ),
      ],
      false,
    );
  }

  final bulan = <DateTime>{for (final h in hari) DateTime(h.year, h.month)};
  return (
    'Pendapatan per bulan',
    [
      for (final b in bulan)
        BatangGrafik(
          DateFormat('MMM', 'id_ID').format(b),
          perBulan[_kunciBulan(b)] ?? 0,
          nama: DateFormat('MMM yyyy', 'id_ID').format(b),
        ),
    ],
    false,
  );
}

/// Rentang jam satu [hari]: dari shift pertama dibuka sampai shift terakhir
/// ditutup (yang masih berjalan: sampai [sekarang]), diperlebar oleh
/// [waktuLain] yang jatuh di luarnya. Null = tidak ada shift maupun data.
///
/// Shift dipotong di batas hari itu. Dulu hanya jamnya yang dibandingkan:
/// shift 18:00–02:00 menjadi rentang 02–23 dengan 16 batang kosong, dan
/// shift lama yang tidak pernah ditutup ikut jam saat laporan dibuka
/// (review D3).
(int, int)? _rentangJam(
  List<Shift> shift,
  Iterable<DateTime> waktuLain,
  DateTime sekarang, {
  required DateTime hari,
}) {
  final awalHari = DateTime(hari.year, hari.month, hari.day);
  final akhirHari = awalHari
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));
  DateTime potong(DateTime w) => w.isBefore(awalHari)
      ? awalHari
      : w.isAfter(akhirHari)
      ? akhirHari
      : w;
  final jam = <int>[
    for (final s in shift) ...[
      potong(s.startAt.toLocal()).hour,
      potong((s.endAt ?? sekarang).toLocal()).hour,
    ],
    for (final w in waktuLain) w.toLocal().hour,
  ];
  if (jam.isEmpty) return null;
  return (
    jam.reduce((a, b) => a < b ? a : b),
    jam.reduce((a, b) => a > b ? a : b),
  );
}

/// Rincian per waktu untuk file unduhan — hanya yang ada isinya:
/// - satu hari: per jam;
/// - sampai 31 hari: per hari;
/// - lebih dari 31 hari: per bulan — baris total bulan, lalu hari-harinya.
List<BarisWaktu> _perWaktu(
  List<DateTime> hari,
  List<Transaction> sah,
  List<Expense> pengeluaran,
) {
  // Setiap transaksi dan pengeluaran dimasukkan sekali ke tumpukan jam/hari/
  // bulannya. Dulu setiap baris menyisir semua transaksi periode itu
  // (audit 6 Nov nomor 56).
  final perJam = <int, _Tumpukan>{};
  final perHari = <int, _Tumpukan>{};
  final perBulan = <int, _Tumpukan>{};
  Iterable<_Tumpukan> tempat(DateTime w) => [
    perJam.putIfAbsent(w.hour, _Tumpukan.new),
    perHari.putIfAbsent(_kunciHari(w), _Tumpukan.new),
    perBulan.putIfAbsent(_kunciBulan(w), _Tumpukan.new),
  ];
  for (final t in sah) {
    for (final k in tempat(t.createdAt.toLocal())) {
      k.tambahTransaksi(t);
    }
  }
  for (final e in pengeluaran) {
    for (final k in tempat(e.createdAt.toLocal())) {
      k.pengeluaran += e.amount;
    }
  }

  BarisWaktu baris(String label, _Tumpukan? k, {bool totalBulan = false}) =>
      BarisWaktu(
        label: label,
        totalBulan: totalBulan,
        transaksi: k?.transaksi ?? 0,
        pendapatan: k?.pendapatan ?? 0,
        tunai: k?.tunai ?? 0,
        qris: k?.qris ?? 0,
        pengeluaran: k?.pengeluaran ?? 0,
      );

  List<BarisWaktu> daftarHari(Iterable<DateTime> daftar) {
    final nama = DateFormat('EEEE, d MMM yyyy', 'id_ID');
    return [
      for (final h in daftar) baris(nama.format(h), perHari[_kunciHari(h)]),
    ].where((b) => !b.kosong).toList();
  }

  if (hari.length == 1) {
    String jam(int h) => h.toString().padLeft(2, '0');
    return [
      for (var h = 0; h < 24; h++)
        baris('${jam(h)}:00 – ${jam(h)}:59', perJam[h]),
    ].where((b) => !b.kosong).toList();
  }
  if (hari.length <= 31) return daftarHari(hari);

  final namaBulan = DateFormat('MMMM yyyy', 'id_ID');
  final bulan = <DateTime>{for (final h in hari) DateTime(h.year, h.month)};
  return [
    for (final b in bulan)
      ...() {
        final total = baris(
          namaBulan.format(b),
          perBulan[_kunciBulan(b)],
          totalBulan: true,
        );
        if (total.kosong) return const <BarisWaktu>[];
        return [
          total,
          ...daftarHari(
            hari.where((h) => h.year == b.year && h.month == b.month),
          ),
        ];
      }(),
  ];
}

/// Jumlah sementara satu jam/hari/bulan selagi [_perWaktu] menghitung.
class _Tumpukan {
  int transaksi = 0;
  int pendapatan = 0;
  int tunai = 0;
  int qris = 0;
  int pengeluaran = 0;

  void tambahTransaksi(Transaction t) {
    transaksi++;
    pendapatan += t.total;
    if (t.paymentMethod == 'qris') {
      qris += t.total;
    } else {
      tunai += t.total;
    }
  }
}

int _kunciHari(DateTime w) => w.year * 10000 + w.month * 100 + w.day;
int _kunciBulan(DateTime w) => w.year * 100 + w.month;

/// Semua produk yang belum dihapus (laku atau tidak), ditambah produk yang
/// sudah dihapus tapi terjual di periode ini. Dikelompokkan per id produk;
/// nama diambil dari produk, atau dari nama yang tercatat di struk kalau
/// produknya sudah tidak ada.
List<PenjualanProduk> _perProduk(
  List<Transaction> sah,
  Map<String, List<TransactionItem>> item,
  List<Product> produk,
  List<Category> kategori,
) {
  final terjual = <String, (String, int, int)>{};
  for (final t in sah) {
    for (final i in item[t.id] ?? const <TransactionItem>[]) {
      final lama = terjual[i.productId];
      terjual[i.productId] = (
        lama?.$1 ?? i.productName,
        (lama?.$2 ?? 0) + i.qty,
        (lama?.$3 ?? 0) + i.subtotal,
      );
    }
  }
  final produkPerId = {for (final p in produk) p.id: p};
  final namaKategori = {for (final k in kategori) k.id: k.name};
  final id = {
    for (final p in produk)
      if (p.deletedAt == null) p.id,
    ...terjual.keys,
  };
  return [
    for (final i in id)
      PenjualanProduk(
        nama: produkPerId[i]?.name ?? terjual[i]!.$1,
        foto: produkPerId[i]?.imagePath,
        kategori: namaKategori[produkPerId[i]?.categoryId] ?? _tanpaKategori,
        terjual: terjual[i]?.$2 ?? 0,
        nilai: terjual[i]?.$3 ?? 0,
        tanpaKategori: !namaKategori.containsKey(produkPerId[i]?.categoryId),
      ),
  ];
}

const _tanpaKategori = 'Tanpa Kategori';

List<PendapatanKategori> _perKategori(
  List<PenjualanProduk> perProduk,
  List<Category> kategori,
) {
  // Per nama, karena pendapatan digabung per nama. Kalau ada beberapa
  // kategori bernama sama, ikon yang terisi yang dipakai — bukan yang
  // terakhir dibaca.
  final ikon = <String, int?>{};
  for (final k in kategori) {
    ikon[k.name] ??= k.iconCodepoint;
  }
  final nilai = <(String, bool), int>{};
  for (final p in perProduk) {
    final kunci = (p.kategori, p.tanpaKategori);
    nilai[kunci] = (nilai[kunci] ?? 0) + p.nilai;
  }
  return [
    for (final MapEntry(key: (nama, tanpa), :value) in nilai.entries)
      PendapatanKategori(
        nama,
        tanpa ? null : ikon[nama],
        value,
        tanpaKategori: tanpa,
      ),
  ]..sort((a, b) => b.nilai.compareTo(a.nilai));
}
