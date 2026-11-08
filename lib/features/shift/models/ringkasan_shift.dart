import 'package:intl/intl.dart';

import 'format_shift.dart';

import '../../../data/app_database.dart';
import '../../expenses/models/kategori_biaya.dart';

/// Satu shift beserta isinya, untuk Riwayat Shift dan Detail Shift.
///
/// [transaksi] dan [pengeluaran] memuat yang DIBATALKAN juga (tampil pudar di
/// Detail Shift), tapi semua angka di sini hanya menghitung yang sah.
class RingkasanShift {
  final Shift shift;
  final String? namaKasir;

  /// Terbaru dulu.
  final List<Transaction> transaksi;

  /// Terbaru dulu.
  final List<Expense> pengeluaran;

  RingkasanShift({
    required this.shift,
    required this.namaKasir,
    required this.transaksi,
    required this.pengeluaran,
  });

  bool get aktif => shift.endAt == null;

  late final List<Transaction> _sah = transaksi
      .where((t) => t.deletedAt == null)
      .toList();

  int get jumlahTransaksi => _sah.length;
  int get pendapatan => _jumlahkan(_sah);
  int get jumlahTunai => _sah.where(_tunai).length;
  int get jumlahQris => jumlahTransaksi - jumlahTunai;
  int get jumlahDelivery => _sah.where(_delivery).length;
  int get jumlahDineIn => jumlahTransaksi - jumlahDelivery;

  int get totalPengeluaran => pengeluaran
      .where((e) => e.deletedAt == null)
      .fold(0, (s, e) => s + e.amount);

  /// Total belanja tunai — bukan uang diterima, karena kembalian sudah
  /// keluar lagi dari laci.
  int get penjualanTunai => _jumlahkan(_sah.where(_tunai));

  /// Dicatat SESUDAH shift ini ditutup — biasanya oleh HP yang sedang
  /// offline saat HP lain menutup shift. Ikut terhitung di kas akhir, jadi
  /// owner perlu tahu.
  bool masukSetelahTutup(DateTime dibuat) {
    final tutup = shift.endAt;
    return tutup != null && dibuat.isAfter(tutup);
  }

  /// Uang yang seharusnya ada di laci: kas awal + penjualan tunai −
  /// pengeluaran shift (keputusan owner: pengeluaran saat shift selalu
  /// diambil dari laci; pengeluaran owner tanpa shift tidak masuk sini).
  /// Null untuk shift lama yang dibuka sebelum ada kas awal. Bisa minus.
  int? get kasAkhir {
    final awal = shift.kasAwal;
    return awal == null ? null : awal + penjualanTunai - totalPengeluaran;
  }

  /// Tabel rincian di Detail Shift (desain): tiap metode bayar dipecah per
  /// tipe pesanan, ditutup baris total metode itu.
  List<BarisRincian> get rincian => [
    for (final (label, tunai) in const [('Cash', true), ('QRIS', false)]) ...[
      for (final (tipe, delivery) in const [
        ('Dine In', false),
        ('Delivery', true),
      ])
        _baris(
          '$label $tipe',
          _sah.where((t) => _tunai(t) == tunai && _delivery(t) == delivery),
        ),
      _baris(
        '$label Total',
        _sah.where((t) => _tunai(t) == tunai),
        tebal: true,
      ),
    ],
  ];

  /// Kotak kategori di bawah Pengeluaran, atas permintaan owner. Ketiganya
  /// selalu tampil. [BarisRincian.jumlah] menghitung catatan, bukan qty.
  List<BarisRincian> get rincianPengeluaran {
    final sah = pengeluaran.where((e) => e.deletedAt == null);
    return [
      for (final k in KategoriBiaya.values)
        () {
          final isi = sah.where((e) => e.category == k.kode);
          return BarisRincian(
            k.label,
            isi.length,
            isi.fold(0, (n, e) => n + e.amount),
            satuan: 'data',
          );
        }(),
    ];
  }

  static bool _tunai(Transaction t) => t.paymentMethod != 'qris';

  /// Selain Delivery = Dine In. Take Away sudah digabung ke Dine In (v34);
  /// transaksi dari HP yang belum diperbarui tetap terhitung Dine In.
  static bool _delivery(Transaction t) => t.orderType == 'delivery';

  static int _jumlahkan(Iterable<Transaction> l) =>
      l.fold(0, (s, t) => s + t.total);

  static BarisRincian _baris(
    String label,
    Iterable<Transaction> l, {
    bool tebal = false,
  }) => BarisRincian(label, l.length, _jumlahkan(l), tebal: tebal);
}

class BarisRincian {
  final String label;
  final int jumlah;
  final int total;

  /// Baris "… Total": tebal, dengan garis pemisah yang lebih gelap.
  final bool tebal;

  /// Sebutan [jumlah]: `trx` untuk transaksi, `data` untuk pengeluaran.
  final String satuan;

  const BarisRincian(
    this.label,
    this.jumlah,
    this.total, {
    this.tebal = false,
    this.satuan = 'trx',
  });
}

/// "7j 0m" (desain). Shift yang masih berjalan dihitung sampai [sekarang].
///
/// Sehari atau lebih: "8 hari 1 jam" (sama dengan [lamaShift]).
String durasiShift(Shift s, DateTime sekarang) {
  final d = (s.endAt ?? sekarang).difference(s.startAt);
  final menit = d.isNegative ? 0 : d.inMinutes;
  if (menit >= 24 * 60) return lamaShift(s.startAt, s.endAt ?? sekarang);
  return '${menit ~/ 60}j ${menit % 60}m';
}

/// "08:00 – 15:00" atau "13:26 – sekarang". Selesai di hari lain ditulis
/// dengan tanggalnya: "22:00 – 10 Nov 02:00". Dulu "22:00 – 02:00", tampak
/// selesai sebelum mulai (audit 6 Nov nomor 50).
String jamShift(Shift s) {
  final f = DateFormat('HH:mm');
  final mulai = s.startAt.toLocal();
  final selesai = s.endAt?.toLocal();
  if (selesai == null) return '${f.format(mulai)} – sekarang';
  final hariSama = selesai.year == mulai.year &&
      selesai.month == mulai.month &&
      selesai.day == mulai.day;
  final akhir = hariSama
      ? f.format(selesai)
      : '${DateFormat('d MMM', 'id_ID').format(selesai)} ${f.format(selesai)}';
  return '${f.format(mulai)} – $akhir';
}

class KelompokShift {
  final DateTime tanggal;
  final List<RingkasanShift> isi;

  const KelompokShift(this.tanggal, this.isi);

  int get pendapatan => isi.fold(0, (s, r) => s + r.pendapatan);
}

/// Dikelompokkan per tanggal MULAI shift, urutan masukan dipertahankan
/// (terbaru dulu dari repositori).
List<KelompokShift> kelompokkanShift(List<RingkasanShift> daftar) {
  final peta = <DateTime, List<RingkasanShift>>{};
  for (final r in daftar) {
    final m = r.shift.startAt.toLocal();
    peta.putIfAbsent(DateTime(m.year, m.month, m.day), () => []).add(r);
  }
  return [for (final e in peta.entries) KelompokShift(e.key, e.value)];
}

/// Judul kelompok (desain): "Hari ini", "Kemarin", atau tanggal lengkap.
String labelHariShift(DateTime tanggal, DateTime hariIni) {
  final h = DateTime(hariIni.year, hariIni.month, hariIni.day);
  final t = DateTime(tanggal.year, tanggal.month, tanggal.day);
  if (t == h) return 'Hari ini';
  if (t == DateTime(h.year, h.month, h.day - 1)) return 'Kemarin';
  return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(t);
}
