import 'package:flutter/material.dart';

import '../../../data/db.dart';
import '../../../shared/auth/cakupan_riwayat.dart';
import '../../../shared/ui/kotak_cari.dart';
import '../../../shared/ui/periode/kartu_periode.dart';
import '../../../shared/ui/periode/bagian_filter.dart';
import '../../../shared/ui/periode/pengawas_hari.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../sales/repositories/sales_repository.dart';
import '../models/saringan_riwayat.dart';
import '../widgets/daftar_riwayat.dart';

/// Riwayat untuk owner (desain): cari · filter periode + metode · kelompok
/// per hari berpita oranye · detail berbentuk struk.
class RiwayatOwnerPage extends StatefulWidget {
  const RiwayatOwnerPage({super.key});

  @override
  State<RiwayatOwnerPage> createState() => _RiwayatOwnerPageState();
}

class _RiwayatOwnerPageState extends State<RiwayatOwnerPage> {
  final _repo = SalesRepository(db);
  final _cakupan = CakupanRiwayat.dariSesi();

  var _periode = Periode.hari(DateTime.now());

  /// Dibiarkan terbuka lewat tengah malam: pintasan seperti "Hari ini"
  /// ikut pindah ke tanggal baru, rentang pilihan sendiri tidak.
  late final _pengawasHari = PengawasHari(
    onGanti: (lama, baru) {
      final p = geserPintasan(_periode, lama, baru);
      if (p != null && mounted) setState(() => _periode = p);
    },
  );

  @override
  void dispose() {
    _pengawasHari.dispose();
    super.dispose();
  }

  /// Kode metode bayar ('cash'/'qris'); null = Semua.
  String? _metode;
  var _cari = '';

  @override
  void initState() {
    super.initState();
    _pengawasHari; // mulai mengawasi
  }

  @override
  Widget build(BuildContext context) {
    return DaftarRiwayat(
      repo: _repo,
      saringan: SaringanRiwayat(
        cakupan: _cakupan,
        periode: _periode,
        metode: _metode,
        cari: _cari,
      ),
      kepala: [
        KotakCari(
          petunjuk: 'Cari riwayat...',
          onBerubah: (v) => setState(() => _cari = v),
        ),
        const SizedBox(height: 12),
        KartuPeriode(
          periode: _periode,
          bagian: BagianFilter.metodeBayar,
          pilihan: _metode,
          ikon: Icons.tune_rounded,
          onBerubah: (p) => setState(() => _periode = p),
          onBerubahPilihan: (m) => setState(() => _metode = m),
        ),
        const SizedBox(height: 16),
      ],
      kosong: (_) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'Riwayat tidak ditemukan',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: TeksTeras.biasa,
            color: WarnaTeras.teksPudar,
          ),
        ),
      ),
    );
  }
}
