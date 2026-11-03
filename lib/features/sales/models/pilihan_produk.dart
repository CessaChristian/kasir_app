import '../../../data/app_database.dart';

/// Kelompok pilihan yang bisa dinyalakan per produk.
///
/// Isi pilihannya kata-kata owner apa adanya — campuran Inggris & Indonesia
/// memang disengaja (keputusan owner 2026-11-02). Semua pilihan berbeda satu
/// sama lain, jadi catatan cukup menyebut pilihannya saja.
enum KelompokPilihan {
  pedas('Pedas', ['Tidak Pedas', 'Sedang Pedas', 'Pedas', 'Ekstra Pedas'],
      'Tidak Pedas'),
  manis('Manis', ['No Sugar', 'Less Sugar', 'Manis', 'Ekstra Sugar'], 'Manis'),
  es('Es', ['Hot', 'No Ice', 'Less Ice', 'Normal Ice', 'Ekstra Ice'],
      'Normal Ice');

  const KelompokPilihan(this.label, this.daftar, this.bawaan);

  final String label;
  final List<String> daftar;

  /// Sudah tertanda saat lembar pilihan dibuka — kasir cukup mengubah yang
  /// diminta pelanggan.
  final String bawaan;

  /// Tingkat [opsi] untuk titik di lembar pilihan: 0 (tanpa) sampai 3
  /// (ekstra). Null untuk "Hot" — bukan tingkat es, ditandai ikon api.
  int? tingkat(String opsi) {
    final i = daftar.indexOf(opsi);
    if (this == es) return i == 0 ? null : i - 1;
    return i;
  }
}

/// Kelompok yang dinyalakan di [p], urut Pedas → Manis → Es.
List<KelompokPilihan> kelompokUntuk(Product p) => [
      if (p.hasSpicyOption) KelompokPilihan.pedas,
      if (p.hasSweetOption) KelompokPilihan.manis,
      if (p.hasIceOption) KelompokPilihan.es,
    ];

/// Ringkasan pilihan untuk daftar produk (desain): satu kelompok =
/// "Level pedas", lebih dari satu = "2 varian", tanpa pilihan = "".
String teksRingkasPilihan(List<KelompokPilihan> kelompok) => switch (kelompok) {
      [] => '',
      [final k] => 'Level ${k.label.toLowerCase()}',
      _ => '${kelompok.length} varian',
    };

/// Catatan untuk item struk: "Less Sugar, Normal Ice" — pilihannya saja,
/// tanpa nama kelompok (keputusan owner 2026-11-02).
///
/// Transaksi & open bill lama tetap menyimpan format lama ("Pedas: Sedang ·
/// Manis: Sedikit") dan ditampilkan apa adanya.
///
/// Urutannya selalu mengikuti [KelompokPilihan], bukan urutan diketuk —
/// keranjang menggabungkan baris berdasarkan catatan ini, jadi pilihan yang
/// sama harus selalu menghasilkan teks yang sama persis.
String catatanDari(Map<KelompokPilihan, String> pilihan) => [
      for (final k in KelompokPilihan.values)
        if (pilihan[k] case final p?) p,
    ].join(', ');
