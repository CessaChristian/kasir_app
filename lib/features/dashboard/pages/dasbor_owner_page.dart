import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/bar_rasio.dart';
import '../../../shared/ui/baris_angka.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/kepala_sapaan.dart';
import '../../../shared/ui/tombol_lembut.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../../shift/pages/riwayat_shift_page.dart';
import '../../shift/models/produk_laris.dart';
import '../../shift/repositories/shift_repository.dart';
import '../repositories/dasbor_owner_repository.dart';
import '../widgets/kisi_produk_laris.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/status_sinkron.dart';
import '../../../utils/pemuat_terakhir.dart';
import '../../perangkat/widgets/peringatan_perangkat.dart';

/// Dashboard owner: satu kartu "Ringkasan hari ini".
class DasborOwnerPage extends StatefulWidget {
  const DasborOwnerPage({super.key});

  @override
  State<DasborOwnerPage> createState() => _DasborOwnerPageState();
}

class _DasborOwnerPageState extends State<DasborOwnerPage> {
  final _repo = DasborOwnerRepository(db);
  RingkasanOwner? _data;
  StreamSubscription<void>? _langganan;
  Timer? _tiapMenit;

  @override
  void initState() {
    super.initState();
    _muat();
    _langganan = _repo.perubahan().listen((_) => _muat());
    // "Kemarin di jam yang sama" bergeser terus walau tidak ada transaksi.
    _tiapMenit = Timer.periodic(const Duration(minutes: 1), (_) => _muat());
  }

  @override
  void dispose() {
    _langganan?.cancel();
    _tiapMenit?.cancel();
    super.dispose();
  }

  final _repoShift = ShiftRepository(db);
  DateTime? _minggu;
  Stream<List<ProdukLaris>>? _aliranLaris;

  /// Produk Paling Laris minggu berjalan; dibuat ulang saat minggu berganti
  /// (pemuatan tiap menit ikut menggambar ulang).
  Stream<List<ProdukLaris>> _laris() {
    final minggu = awalMinggu(DateTime.now());
    if (minggu != _minggu) {
      _minggu = minggu;
      _aliranLaris = _repoShift.watchProdukLarisMinggu(minggu);
    }
    return _aliranLaris!;
  }

  final _pemuat = PemuatTerakhir();

  Future<void> _muat() => _pemuat.jalankan(_repo.muat, (data) {
    if (mounted) setState(() => _data = data);
  });

  @override
  Widget build(BuildContext context) {
    final data = _data;
    // Tanpa tarik-untuk-refresh: refresh lewat tombol di header, dan isinya
    // memuat ulang sendiri karena mendengarkan perubahan database.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (data == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // Owner membaca laporan dari data di HP ini: kalau sinkronnya macet,
          // angka di bawah bisa kurang tanpa ada yang tahu.
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: StatusSinkron(hanyaPeringatan: true),
          ),
          const PeringatanPerangkat(),
          _kartuRingkasan(data),
          // Hanya dilihat: owner tidak menjual.
          StreamBuilder<List<ProdukLaris>>(
            stream: _laris(),
            builder: (context, snap) => snap.hasData
                ? KisiProdukLaris(daftar: snap.data!)
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _kartuRingkasan(RingkasanOwner d) {
    final persen = d.persenVsKemarin;
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sapaan(),
          const GarisTeras(),
          const Text('Pendapatan hari ini',
              style: TextStyle(fontSize: TeksTeras.kecil, color: WarnaTeras.teksPudar)),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                formatRp(d.pendapatan),
                style: const TextStyle(
                  fontSize: TeksTeras.angkaBesar,
                  fontWeight: FontWeight.w700,
                  color: WarnaTeras.oranye,
                ),
              ),
              if (persen != null) _lencanaPersen(persen),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'vs kemarin di jam yang sama (${formatRp(d.pendapatanKemarin)})',
            style: const TextStyle(fontSize: TeksTeras.keterangan, color: WarnaTeras.teksSamar),
          ),
          const SizedBox(height: 14),
          BarisAngka(isi: [
            Angka('Transaksi', '${d.transaksi}'),
            Angka('Pengeluaran', formatRp(d.pengeluaran),
                warna: WarnaTeras.merah),
            Angka('Laba kotor', formatRp(d.labaKotor),
                warna: WarnaTeras.hijau),
          ]),
          const SizedBox(height: 16),
          BarRasio(
            kiri: d.tunai,
            kanan: d.qris,
            labelKiri: 'Tunai ${d.tunai} transaksi',
            labelKanan: 'QRIS ${d.qris} transaksi',
          ),
          const GarisTeras(),
          _statusShift(d),
          const SizedBox(height: 12),
          TombolLembut(
            ikon: Icons.history_rounded,
            label: 'Lihat Riwayat Shift',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RiwayatShiftPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sapaan() => KepalaSapaan(
    nama: SessionManager.instance.currentSession?.username ?? '',
    ikon: Icons.storefront_rounded,
    lencana: const LencanaSapaan('Ringkasan hari ini'),
  );

  Widget _lencanaPersen(int persen) {
    final naik = persen >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: naik ? WarnaTeras.hijauMuda : WarnaTeras.merahMuda,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            naik ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: naik ? WarnaTeras.hijau : WarnaTeras.merah,
          ),
          const SizedBox(width: 2),
          Text(
            '${naik ? '+' : ''}$persen%',
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w600,
              color: naik ? WarnaTeras.hijau : WarnaTeras.merah,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusShift(RingkasanOwner d) {
    final jam = DateFormat('HH:mm');
    final berjalan = d.shiftBerjalan;
    final String judul;
    final String keterangan;
    if (berjalan.isEmpty) {
      judul = 'Tidak ada shift aktif';
      keterangan = d.shiftTerakhirDitutup == null
          ? 'Belum ada shift hari ini'
          : 'Shift terakhir ditutup ${jam.format(d.shiftTerakhirDitutup!)}';
    } else if (berjalan.length == 1) {
      final s = berjalan.single;
      judul = '${s.namaKasir} sedang shift';
      keterangan = 'Sejak ${jam.format(s.mulai)} · ${s.transaksi} transaksi'
          ' · ${formatRp(s.pendapatan)}';
    } else {
      // Dua HP bisa menjalankan shift bersamaan.
      final nama = berjalan.map((s) => s.namaKasir).toList();
      judul = '${nama.sublist(0, nama.length - 1).join(', ')} & ${nama.last}'
          ' sedang shift';
      keterangan = '${berjalan.length} shift'
          ' · ${berjalan.fold(0, (a, s) => a + s.transaksi)} transaksi'
          ' · ${formatRp(berjalan.fold(0, (a, s) => a + s.pendapatan))}';
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: berjalan.isEmpty ? WarnaTeras.titikPasif : WarnaTeras.hijau,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(judul,
                  style: const TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks)),
              const SizedBox(height: 1),
              Text(keterangan,
                  style: const TextStyle(
                      fontSize: TeksTeras.keterangan, color: WarnaTeras.teksPudar)),
            ],
          ),
        ),
      ],
    );
  }
}
