/// Rentang tanggal untuk filter halaman (Pengeluaran, nanti Riwayat,
/// Laporan, Riwayat Shift). Keduanya TANGGAL saja dan inklusif.
class Periode {
  final DateTime dari;
  final DateTime sampai;

  Periode(DateTime dari, DateTime sampai)
    : dari = _tanggal(dari),
      sampai = _tanggal(sampai);

  /// Satu hari penuh.
  Periode.hari(DateTime hari) : this(hari, hari);

  static DateTime _tanggal(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Batas akhir EKSKLUSIF untuk kueri `created_at < batasAkhir`.
  DateTime get batasAkhir =>
      DateTime(sampai.year, sampai.month, sampai.day + 1);

  bool get satuHari => dari == sampai;

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
    ('Hari ini', Periode.hari(h)),
    ('Kemarin', Periode.hari(geser(-1))),
    ('7 Hari Terakhir', Periode(geser(-6), h)),
    ('30 Hari Terakhir', Periode(geser(-29), h)),
    ('Bulan Ini', Periode(DateTime(h.year, h.month), h)),
    (
      'Bulan Lalu',
      Periode(DateTime(h.year, h.month - 1), DateTime(h.year, h.month, 0)),
    ),
  ];
}

/// "Hari ini", "Bulan Lalu", ... atau "Filter periode".
String namaPeriode(Periode p, DateTime hariIni) {
  for (final (nama, q) in pintasanPeriode(hariIni)) {
    if (q == p) return nama;
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
