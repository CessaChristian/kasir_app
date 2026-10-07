import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../data/db.dart';
import '../../../shared/auth/cakupan_riwayat.dart';
import '../../../shared/ui/kotak_cari.dart';
import '../../../shared/ui/periode/kartu_periode.dart';
import '../../../shared/ui/periode/bagian_filter.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../shared/ui/pita_hari.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../../sales/repositories/sales_repository.dart';
import '../models/kelompok_riwayat.dart';
import '../widgets/baris_transaksi.dart';
import '../widgets/batalkan_transaksi.dart';

/// Riwayat untuk owner (desain): cari · filter periode + metode · kelompok
/// per hari berpita oranye · detail berbentuk struk.
class RiwayatOwnerPage extends StatefulWidget {
  const RiwayatOwnerPage({super.key});

  @override
  State<RiwayatOwnerPage> createState() => _RiwayatOwnerPageState();
}

class _RiwayatOwnerPageState extends State<RiwayatOwnerPage> {
  final _repo = SalesRepository(db);

  // Dibuat sekali — stream yang dibuat ulang tiap build membuat daftar
  // berkedip.
  late final _riwayat = _repo.watchRiwayat(CakupanRiwayat.dariSesi());

  var _periode = Periode.hari(DateTime.now());

  /// Kode metode bayar ('cash'/'qris'); null = Semua.
  String? _metode;
  var _cari = '';
  Set<String> _idCocokMenu = const {};

  /// Hari yang dilipat. Kosong = semua terbuka (desain).
  final _terlipat = <DateTime>{};
  Map<String, String> _nama = const {};

  @override
  void initState() {
    super.initState();
    _repo.namaAkun().then((m) {
      if (mounted) setState(() => _nama = m);
    });
  }

  Future<void> _ubahCari(String v) async {
    setState(() => _cari = v);
    final id = await _repo.idTransaksiBerisiMenu(v);
    // Abaikan jawaban untuk kata cari yang sudah diganti.
    if (mounted && v == _cari) setState(() => _idCocokMenu = id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: _riwayat,
      builder: (context, snap) {
        final hari = snap.hasData
            ? kelompokkanRiwayat(
                snap.data!,
                periode: _periode,
                metode: _metode,
                cari: _cari,
                idCocokMenu: _idCocokMenu,
              )
            : null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KotakCari(petunjuk: 'Cari riwayat...', onBerubah: _ubahCari),
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
            if (hari == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hari.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Riwayat tidak ditemukan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              )
            else
              for (final h in hari) ...[
                PitaHari(
                  judul: DateFormat(
                    'EEEE, d MMM yyyy',
                    'id_ID',
                  ).format(h.tanggal),
                  keterangan: '${h.isi.length} Transaksi',
                  total: formatRp(h.total),
                  terbuka: !_terlipat.contains(h.tanggal),
                  onTap: () => setState(() {
                    if (!_terlipat.remove(h.tanggal)) _terlipat.add(h.tanggal);
                  }),
                  isi: [
                    for (final t in h.isi)
                      BarisTransaksi(
                        transaksi: t,
                        namaPembatal: t.namaPembatal(_nama),
                        onTap: () => bukaDetailTransaksi(context, _repo, t),
                        onBatalkan: _repo.bolehDibatalkan(t)
                            ? () => batalkanTransaksiLewatDialog(
                                context,
                                _repo,
                                t,
                              )
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }
}
