/// Rentang tanggal untuk filter halaman (Pengeluaran, nanti Riwayat,
/// Laporan, Riwayat Shift). Keduanya TANGGAL saja dan inklusif.
class Periode {
  final DateTime dari;
  final DateTime sampai;

  /// Nama pintasan yang dipilih owner ("Bulan Ini"), null untuk rentang
  /// pilihan sendiri. Tidak ikut dibandingkan di `==`. Dua pintasan bisa
  /// bertanggal sama — tanggal 7, "Bulan Ini" = "7 Hari Terakhir" — dan dulu
  /// namanya ditebak dari tanggal: judulnya salah, dan lewat tengah malam
  /// "Bulan Ini" bergeser jadi 7 hari terakhir sehingga tanggal 1 hilang
  /// (audit 6 Nov nomor 38).
  final String? nama;

  Periode(DateTime dari, DateTime sampai, {this.nama})
    : dari = _tanggal(dari),
      sampai = _tanggal(sampai);

  /// Satu hari penuh.
  Periode.hari(DateTime hari, {String? nama}) : this(hari, hari, nama: nama);

  static DateTime _tanggal(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Batas akhir EKSKLUSIF untuk kueri `created_at < batasAkhir`.
  DateTime get batasAkhir =>
      DateTime(sampai.year, sampai.month, sampai.day + 1);

  bool get satuHari => dari == sampai;

  /// Lebih panjang dari 12 bulan, mis. 1 Jan 2026 – 1 Jan 2027 (1 Jan –
  /// 31 Des masih boleh). Unduh laporan dibatasi 12 bulan sekali: file PDF
  /// setahun lebih jadi sangat besar dan lama dibuat (keputusan owner
  /// 2026-10-28). Tampilan Laporan di layar tidak dibatasi.
  bool get lebihDari12Bulan =>
      !sampai.isBefore(DateTime(dari.year + 1, dari.month, dari.day));

  @override
  bool operator ==(Object other) =>
      other is Periode && other.dari == dari && other.sampai == sampai;

  @override
  int get hashCode => Object.hash(dari, sampai);
}

const namaBulanPendek = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const namaBulanPanjang = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', //
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// Enam pilihan cepat di desain, berurutan.
List<(String, Periode)> pintasanPeriode(DateTime hariIni) {
  final h = DateTime(hariIni.year, hariIni.month, hariIni.day);
  DateTime geser(int n) => DateTime(h.year, h.month, h.day + n);
  return [
    ('Hari ini', Periode.hari(h, nama: 'Hari ini')),
    ('Kemarin', Periode.hari(geser(-1), nama: 'Kemarin')),
    ('7 Hari Terakhir', Periode(geser(-6), h, nama: '7 Hari Terakhir')),
    ('30 Hari Terakhir', Periode(geser(-29), h, nama: '30 Hari Terakhir')),
    ('Bulan Ini', Periode(DateTime(h.year, h.month), h, nama: 'Bulan Ini')),
    (
      'Bulan Lalu',
      Periode(
        DateTime(h.year, h.month - 1),
        DateTime(h.year, h.month, 0),
        nama: 'Bulan Lalu',
      ),
    ),
  ];
}

/// Pintasan yang sama untuk hari [baru], kalau [p] adalah pintasan di hari
/// [lama] ("Hari ini" kemarin → "Hari ini" sekarang). Null untuk rentang
/// yang dipilih sendiri — itu tidak digeser.
Periode? geserPintasan(Periode p, DateTime lama, DateTime baru) {
  final nama = namaPeriode(p, lama);
  for (final (n, q) in pintasanPeriode(baru)) {
    if (n == nama) return q;
  }
  return null;
}

/// "Hari ini", "Bulan Lalu", ... atau "Filter periode".
///
/// Nama yang dipilih owner dipakai selama tanggalnya masih cocok. Tanpa nama
/// (rentang dari kalender atau pilihan bulan), bulan didahulukan: pilih
/// "November" di tanggal 7 terbaca "Bulan Ini", bukan "7 Hari Terakhir".
String namaPeriode(Periode p, DateTime hariIni) {
  final pintasan = pintasanPeriode(hariIni);
  for (final (nama, q) in pintasan) {
    if (nama == p.nama && q == p) return nama;
  }
  const urutanTebak = [
    'Hari ini',
    'Kemarin',
    'Bulan Ini',
    'Bulan Lalu',
    '7 Hari Terakhir',
    '30 Hari Terakhir',
  ];
  for (final n in urutanTebak) {
    for (final (nama, q) in pintasan) {
      if (nama == n && q == p) return nama;
    }
  }
  return 'Filter periode';
}

String labelTanggal(DateTime d) =>
    '${d.day} ${namaBulanPendek[d.month - 1]} ${d.year}';

/// "1 Okt 2026" · "1 – 7 Okt 2026" · "28 Sep – 4 Okt 2026" ·
/// "28 Des 2025 – 3 Jan 2026" (format desain).
String labelPeriode(Periode p) {
  if (p.satuHari) return labelTanggal(p.dari);
  final a = p.dari, b = p.sampai;
  if (a.year != b.year) return '${labelTanggal(a)} – ${labelTanggal(b)}';
  if (a.month == b.month) return '${a.day} – ${labelTanggal(b)}';
  return '${a.day} ${namaBulanPendek[a.month - 1]} – ${labelTanggal(b)}';
}

/// Rentang dari awal bulan [awal] sampai akhir bulan [akhir], dipotong di
/// [hariIni] — tidak ada data dari masa depan.
Periode periodeBulan(DateTime awal, DateTime akhir, DateTime hariIni) {
  final h = DateTime(hariIni.year, hariIni.month, hariIni.day);
  final akhirBulan = DateTime(akhir.year, akhir.month + 1, 0);
  return Periode(
    DateTime(awal.year, awal.month),
    akhirBulan.isAfter(h) ? h : akhirBulan,
  );
}
