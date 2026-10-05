import 'package:intl/intl.dart';

import '../../../data/app_database.dart';

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

  const BarisRincian(this.label, this.jumlah, this.total, {this.tebal = false});
}

/// "7j 0m" (desain). Shift yang masih berjalan dihitung sampai [sekarang].
String durasiShift(Shift s, DateTime sekarang) {
  final d = (s.endAt ?? sekarang).difference(s.startAt);
  final menit = d.isNegative ? 0 : d.inMinutes;
  return '${menit ~/ 60}j ${menit % 60}m';
}

/// "08:00 – 15:00" atau "13:26 – sekarang".
String jamShift(Shift s) {
  final f = DateFormat('HH:mm');
  final akhir = s.endAt == null ? 'sekarang' : f.format(s.endAt!.toLocal());
  return '${f.format(s.startAt.toLocal())} – $akhir';
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
