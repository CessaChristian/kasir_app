import '../../../data/app_database.dart';

/// Kelompok pilihan yang bisa dinyalakan per produk.
enum KelompokPilihan {
  pedas('Pedas', ['Tidak Pedas', 'Sedang', 'Pedas', 'Ekstra Pedas'],
      'Tidak Pedas'),
  manis('Manis', ['Tanpa Gula', 'Sedikit', 'Normal', 'Ekstra Gula'], 'Normal'),
  es('Es', ['Tanpa Es', 'Sedikit', 'Normal', 'Ekstra Es'], 'Normal');

  const KelompokPilihan(this.label, this.daftar, this.bawaan);

  final String label;
  final List<String> daftar;

  /// Sudah tertanda saat lembar pilihan dibuka — kasir cukup mengubah yang
  /// diminta pelanggan.
  final String bawaan;
}

/// Kelompok yang dinyalakan di [p], urut Pedas → Manis → Es.
List<KelompokPilihan> kelompokUntuk(Product p) => [
      if (p.hasSpicyOption) KelompokPilihan.pedas,
      if (p.hasSweetOption) KelompokPilihan.manis,
      if (p.hasIceOption) KelompokPilihan.es,
    ];

/// Catatan untuk item struk: "Pedas: Sedang · Manis: Sedikit · Es: Normal".
///
/// Nama kelompok sengaja ikut ditulis: "Sedikit" dan "Normal" ada di dua
/// kelompok, dan tanpa namanya dapur tidak tahu itu gula atau es.
///
/// Urutannya selalu mengikuti [KelompokPilihan], bukan urutan diketuk —
/// keranjang menggabungkan baris berdasarkan catatan ini, jadi pilihan yang
/// sama harus selalu menghasilkan teks yang sama persis.
String catatanDari(Map<KelompokPilihan, String> pilihan) => [
      for (final k in KelompokPilihan.values)
        if (pilihan[k] != null) '${k.label}: ${pilihan[k]}',
    ].join(' · ');
