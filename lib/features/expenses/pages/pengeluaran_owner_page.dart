import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/bar_kategori.dart';
import '../../../shared/ui/judul_bagian.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/periode/bagian_filter.dart';
import '../../../shared/ui/periode/kartu_periode.dart';
import '../../../shared/ui/periode/pengawas_hari.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_tambah.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/kategori_biaya.dart';
import '../models/ringkasan_pengeluaran.dart';
import '../repositories/expense_repository.dart';
import '../widgets/dialog_pengeluaran.dart';
import '../widgets/kelompok_hari_pengeluaran.dart';
import '../../../utils/pesan_galat.dart';

/// Pengeluaran untuk owner: per periode, ringkasan per kategori, rincian per
/// hari. Owner juga bisa mencatat pengeluaran sendiri — tanpa shift, jadi
/// hanya masuk pengelompokan per tanggal (keputusan owner 2026-10-04).
class PengeluaranOwnerPage extends StatefulWidget {
  const PengeluaranOwnerPage({super.key});

  @override
  State<PengeluaranOwnerPage> createState() => _PengeluaranOwnerPageState();
}

class _PengeluaranOwnerPageState extends State<PengeluaranOwnerPage> {
  final _repo = ExpenseRepository(db);
  var _periode = Periode.hari(DateTime.now());

  /// Dibiarkan terbuka lewat tengah malam: pintasan seperti "Hari ini"
  /// ikut pindah ke tanggal baru, rentang pilihan sendiri tidak.
  late final _pengawasHari = PengawasHari(
    onGanti: (lama, baru) {
      final p = geserPintasan(_periode, lama, baru);
      if (p != null && mounted) _ubahPeriode(p);
    },
  );

  @override
  void dispose() {
    _pengawasHari.dispose();
    _langgananNama?.cancel();
    super.dispose();
  }

  /// Kode kategori biaya yang disaring; null = Semua.
  String? _kategori;

  /// Bagian "Kategori biaya" di lembar filter (desain): chip tanpa ikon,
  /// digeser ke samping.
  static final _bagianKategori = BagianFilter(
    judulLembar: 'Filter Pengeluaran',
    judul: 'Kategori biaya',
    lebarSama: false,
    opsi: [
      const OpsiFilter(kode: null, label: 'Semua'),
      for (final k in KategoriBiaya.values)
        OpsiFilter(kode: k.kode, label: k.label),
    ],
  );
  late Stream<List<Expense>> _aliran = _repo.watchPengeluaranPeriode(_periode);
  Map<String, String> _nama = const {};

  @override
  void initState() {
    super.initState();
    _pengawasHari; // mulai mengawasi
    // Ikut berubah saat sinkron membawa akun/nama baru (QA kedua K7).
    _langgananNama = _repo.watchNamaAkun().listen((m) {
      if (mounted) setState(() => _nama = m);
    });
  }

  StreamSubscription<Map<String, String>>? _langgananNama;

  Future<void> _catat() async {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) return;
    final isian = await tampilkanDialogPengeluaran(
      context,
      subjudul: 'Pengeluaran di luar shift',
    );
    if (isian == null || !mounted) return;
    try {
      await _repo.addExpense(
        shiftId: null,
        userId: sesi.userId,
        description: isian.keterangan,
        amount: isian.amount,
        category: isian.kategori.kode,
        qty: isian.qty,
      );
      if (mounted) AppToast.success(context, 'Pengeluaran dicatat');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, pesanGalat(e, awalan: 'Gagal mencatat'));
      }
    }
  }

  void _ubahPeriode(Periode p) => setState(() {
    _periode = p;
    _aliran = _repo.watchPengeluaranPeriode(p);
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Expense>>(
      stream: _aliran,
      builder: (context, snap) {
        // Data periode lama tidak ditampilkan selagi periode baru dimuat —
        // lihat LaporanPage.
        final r = snap.hasData && snap.connectionState != ConnectionState.waiting
            ? ringkasPengeluaran(snap.data!, kategori: _kategori)
            : null;
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                KartuPeriode(
                  periode: _periode,
                  onBerubah: _ubahPeriode,
                  bagian: _bagianKategori,
                  pilihan: _kategori,
                  onBerubahPilihan: (k) => setState(() => _kategori = k),
                ),
                const SizedBox(height: 14),
                if (r == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _ringkasan(r),
                  const SizedBox(height: 22),
                  const JudulBagian('Rincian Pengeluaran', ukuran: 18),
                  const SizedBox(height: 12),
                  if (r.kosong)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Tidak ada pengeluaran di periode ini',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: TeksTeras.biasa,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    )
                  else
                    for (final h in r.perHari) ...[
                      KelompokHariPengeluaran(hari: h, repo: _repo, nama: _nama),
                      const SizedBox(height: 14),
                    ],
                ],
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: TombolTambah(
                tooltip: 'Catat pengeluaran',
                ukuran: 46,
                sudut: 6,
                onTap: _catat,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ringkasan(RingkasanPengeluaran r) {
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total pengeluaran',
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatRp(r.total),
            style: const TextStyle(
              fontSize: TeksTeras.angkaBesar,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.merah,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${r.jumlahItem} item · ${r.jumlahHari} hari',
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.teksSamar,
            ),
          ),
          if (r.perKategori.isNotEmpty) ...[
            const GarisTeras(),
            for (final (label, nilai) in r.perKategori) ...[
              BarKategori(label: label, nilai: nilai, total: r.total),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}
