import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';

/// Satu kartu di Kelola Kasir: akun, shift terakhirnya, dan jumlah izin.
class RingkasanKasir {
  final User akun;

  /// Mulai shift yang sedang berjalan; null = tidak sedang shift.
  final DateTime? mulaiShiftBerjalan;

  /// Kapan shift terakhirnya ditutup; null = belum pernah selesai shift.
  final DateTime? selesaiShiftTerakhir;
  final int izinAktif;
  final int izinTotal;

  const RingkasanKasir({
    required this.akun,
    required this.mulaiShiftBerjalan,
    required this.selesaiShiftTerakhir,
    required this.izinAktif,
    required this.izinTotal,
  });
}

/// Baris di bawah nama kasir (desain): "Shift aktif sejak 13:26",
/// "Shift terakhir 22 Sep 2026, 21:04", atau "Belum pernah shift".
String labelStatusShift({
  required DateTime? mulaiBerjalan,
  required DateTime? selesaiTerakhir,
  required DateTime sekarang,
}) {
  if (mulaiBerjalan != null) {
    final m = mulaiBerjalan.toLocal();
    final hariIni =
        m.year == sekarang.year &&
        m.month == sekarang.month &&
        m.day == sekarang.day;
    final jam = DateFormat('HH:mm').format(m);
    return hariIni
        ? 'Shift aktif sejak $jam'
        : 'Shift aktif sejak ${DateFormat('d MMM', 'id_ID').format(m)}, $jam';
  }
  if (selesaiTerakhir != null) {
    return 'Shift terakhir '
        '${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(selesaiTerakhir.toLocal())}';
  }
  return 'Belum pernah shift';
}

/// Satu izin di halaman Hak Akses (desain): label, keterangan, ikon.
class DefinisiIzin {
  final String kode;
  final String label;
  final String keterangan;
  final IconData ikon;

  const DefinisiIzin(this.kode, this.label, this.keterangan, this.ikon);
}

/// Kelompok izin di halaman Hak Akses, urut sesuai desain. Izin yang ada di
/// database tapi belum terdaftar di sini masuk kelompok "LAINNYA" dengan
/// nama dari database — supaya izin baru tidak hilang dari layar.
const kelompokIzin = <(String, List<DefinisiIzin>)>[
  (
    'OPERASIONAL',
    [
      DefinisiIzin(
        'open_close_shift',
        'Buka Shift',
        'Membuka dan menutup shift',
        Icons.schedule_rounded,
      ),
      DefinisiIzin(
        'create_transaction',
        'Buat Transaksi',
        'Akses halaman kasir',
        Icons.point_of_sale_rounded,
      ),
      DefinisiIzin(
        'view_history',
        'Lihat Riwayat Lengkap',
        'Melihat transaksi & struk',
        Icons.receipt_long_rounded,
      ),
    ],
  ),
  (
    'LAPORAN',
    [
      DefinisiIzin(
        'view_report',
        'Lihat Laporan',
        'Pendapatan & produk terlaris',
        Icons.bar_chart_rounded,
      ),
      DefinisiIzin(
        'view_all_shifts',
        'Lihat Shift Semua Kasir',
        'Riwayat shift kasir lain',
        Icons.groups_rounded,
      ),
    ],
  ),
  (
    'MANAJEMEN',
    [
      DefinisiIzin(
        'manage_products',
        'Kelola Produk',
        'Tambah, ubah, hapus produk',
        Icons.inventory_2_outlined,
      ),
    ],
  ),
];

/// Kelompok untuk izin yang ada di [semua] (dari database), urut desain.
List<(String, List<DefinisiIzin>)> kelompokIzinDari(List<Permission> semua) {
  final ada = {for (final p in semua) p.code};
  final dikenal = {
    for (final (_, isi) in kelompokIzin)
      for (final d in isi) d.kode,
  };
  final hasil = <(String, List<DefinisiIzin>)>[
    for (final (judul, isi) in kelompokIzin)
      if (isi.any((d) => ada.contains(d.kode)))
        (
          judul,
          [
            for (final d in isi)
              if (ada.contains(d.kode)) d,
          ],
        ),
  ];
  final lain = [
    for (final p in semua)
      if (!dikenal.contains(p.code))
        DefinisiIzin(p.code, p.name, p.description, Icons.security_rounded),
  ];
  if (lain.isNotEmpty) hasil.add(('LAINNYA', lain));
  return hasil;
}
