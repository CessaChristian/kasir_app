import 'package:flutter/material.dart';

import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/periode/kartu_periode.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/ringkasan_shift.dart';
import '../repositories/shift_repository.dart';
import '../widgets/kartu_shift.dart';
import 'detail_shift_page.dart';

/// Riwayat Shift (desain): periode · ringkasan Shift/Transaksi/Pendapatan ·
/// kelompok per tanggal · kartu shift → Detail Shift.
///
/// Hak semua akun. Owner dan pemegang izin `view_all_shifts` melihat shift
/// semua kasir; selain itu hanya shift miliknya sendiri.
class RiwayatShiftPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final ShiftRepository? repo;

  const RiwayatShiftPage({super.key, this.repo});

  @override
  State<RiwayatShiftPage> createState() => _RiwayatShiftPageState();
}

class _RiwayatShiftPageState extends State<RiwayatShiftPage> {
  late final _repo = widget.repo ?? ShiftRepository(db);
  var _periode = Periode.hari(DateTime.now());
  late Stream<List<RingkasanShift>> _aliran = _pantau(_periode);

  Stream<List<RingkasanShift>> _pantau(Periode p) {
    final sesi = SessionManager.instance;
    final semua = sesi.hasCurrentPermission('view_all_shifts');
    return _repo.watchRiwayatShift(
      p,
      hanyaUserId: semua ? null : sesi.currentUserId,
    );
  }

  void _ubahPeriode(Periode p) => setState(() {
    _periode = p;
    _aliran = _pantau(p);
  });

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Riwayat Shift',
      child: StreamBuilder<List<RingkasanShift>>(
        stream: _aliran,
        builder: (context, snap) {
          final daftar = snap.data;
          final sekarang = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              KartuPeriode(periode: _periode, onBerubah: _ubahPeriode),
              const SizedBox(height: 14),
              if (daftar == null)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _ringkasan(daftar),
                const SizedBox(height: 16),
                if (daftar.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Tidak ada shift di periode ini',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  )
                else
                  for (final k in kelompokkanShift(daftar)) ...[
                    _kelompok(k, sekarang),
                    const SizedBox(height: 18),
                  ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _ringkasan(List<RingkasanShift> daftar) {
    final transaksi = daftar.fold(0, (s, r) => s + r.jumlahTransaksi);
    final pendapatan = daftar.fold(0, (s, r) => s + r.pendapatan);
    Widget kolom(String label, String nilai, Color warna, {bool garis = true}) {
      return Container(
        padding: EdgeInsets.only(left: garis ? 12 : 0),
        decoration: garis
            ? const BoxDecoration(
                border: Border(left: BorderSide(color: WarnaTeras.garis)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: TeksTeras.keterangan,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                nilai,
                style: TextStyle(
                  fontSize: TeksTeras.angka,
                  fontWeight: FontWeight.w700,
                  color: warna,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Kolom desain 1 : 1 : 1.4.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 10,
            child: kolom(
              'Shift',
              '${daftar.length}',
              WarnaTeras.teks,
              garis: false,
            ),
          ),
          Expanded(
            flex: 10,
            child: kolom('Transaksi', '$transaksi', WarnaTeras.teks),
          ),
          Expanded(
            flex: 14,
            child: kolom('Pendapatan', formatRp(pendapatan), WarnaTeras.oranye),
          ),
        ],
      ),
    );
  }

  Widget _kelompok(KelompokShift k, DateTime sekarang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  labelHariShift(k.tanggal, sekarang),
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w700,
                    color: WarnaTeras.teks,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${k.isi.length} shift · ${formatRp(k.pendapatan)}',
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.teksPudar,
                ),
              ),
            ],
          ),
        ),
        for (final r in k.isi) ...[
          KartuShift(
            ringkasan: r,
            sekarang: sekarang,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DetailShiftPage(shiftId: r.shift.id, repo: widget.repo),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
