import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../data/nama_tercatat.dart';
import '../../shared/auth/cakupan_riwayat.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/ui/judul_bagian.dart';
import '../../shared/ui/kartu_teras.dart';
import '../../shared/ui/tombol_tambah.dart';
import '../../shared/ui/warna_teras.dart';
import '../../shared/widgets/app_toast.dart';
import '../../utils/currency_formatter.dart';
import '../shift/models/ringkasan_shift.dart';
import '../shift/pages/detail_shift_page.dart';
import '../shift/widgets/kartu_shift_lipat.dart';
import '../shift/repositories/shift_repository.dart';
import 'models/ringkasan_pengeluaran.dart';
import 'repositories/expense_repository.dart';
import 'widgets/baris_pengeluaran.dart';
import 'widgets/batalkan_pengeluaran.dart';
import 'widgets/dialog_pengeluaran.dart';
import 'widgets/kelompok_hari_pengeluaran.dart';

/// Shift mana yang layak muncul di "Riwayat Pengeluaran".
///
/// Dipisah dari halamannya supaya bisa diuji — dulu aturannya terkubur di
/// dalam pemuat data, jadi satu-satunya cara memeriksanya adalah lewat
/// emulator, dan dua kekeliruan di bawah lolos karenanya.
///
/// ── SHIFT YANG MASIH BERJALAN IKUT ──
///
/// Dulu syaratnya `endAt != null` — hanya shift yang sudah ditutup. Akibatnya
/// pengeluaran kasir yang sedang bertugas tidak terlihat sampai shiftnya
/// ditutup. Untuk halaman yang gunanya mengawasi, itu titik buta.
///
/// ── SHIFT AKTIF SENDIRI TIDAK IKUT ──
///
/// Punya sendiri sudah tampil utuh di bagian "Shift Aktif" di atasnya.
///
/// ── SHIFT KOSONG TIDAK IKUT ──
///
/// Ini riwayat PENGELUARAN. Shift tanpa satu pun catatan tidak menambah
/// keterangan apa pun.
List<ShiftEntry> riwayatLayakTampil({
  required List<ShiftEntry> semua,
  required Map<String, List<Expense>> perShift,
  required String? shiftAktifSaya,
}) {
  return semua
      .where(
        (e) =>
            e.shift.id != shiftAktifSaya &&
            (perShift[e.shift.id]?.isNotEmpty ?? false),
      )
      .toList();
}

/// Halaman Pengeluaran KASIR (desain): Shift Aktif · Rincian Pengeluaran ·
/// tombol tambah; tanpa shift kartu "Belum ada pengeluaran".
///
/// "Riwayat Pengeluaran" (shift-shift sebelumnya) TIDAK ada di desain, tapi
/// dipertahankan untuk kasir yang punya izin Lihat Riwayat Lengkap supaya
/// bisa langsung mencari (keputusan owner 2026-10-13); tampilannya mengikuti
/// gaya desain. Owner memakai `PengeluaranOwnerPage`.
class ExpensesPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final ExpenseRepository? repo;
  final ShiftRepository? repoShift;

  const ExpensesPage({super.key, this.repo, this.repoShift});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  late final _repo = widget.repo ?? ExpenseRepository(db);
  late final _repoShift = widget.repoShift ?? ShiftRepository(db);

  Map<String, String> _nama = const {};
  Stream<List<Expense>>? _aliranAktif;
  Stream<RingkasanShift?>? _aliranShift;

  final _cakupan = CakupanRiwayat.dariSesi();
  List<ShiftEntry> _riwayat = const [];
  Map<String, List<Expense>> _perShift = const {};
  StreamSubscription<void>? _langgananRiwayat;

  String? get _shiftId => SessionManager.instance.currentSession?.shiftId;
  bool get _bolehLihatRiwayat => _cakupan.jenis != JenisCakupan.shiftAktif;

  @override
  void initState() {
    super.initState();
    final sesi = SessionManager.instance.currentSession;
    final shiftId = sesi?.shiftId;
    if (shiftId != null) {
      _aliranAktif = _repo.watchExpensesByShift(shiftId);
      _aliranShift = _repoShift.watchShift(shiftId);
    } else if (sesi != null) {
      _aliranShift = _repoShift.watchShiftTerakhirSelesai(sesi.userId);
    }
    _langgananRiwayat = _repo.perubahanRiwayat().listen((_) => _muat());
  }

  @override
  void dispose() {
    _langgananRiwayat?.cancel();
    super.dispose();
  }

  /// Nama akun dan riwayat; dimuat ulang tiap ada perubahan (termasuk dari
  /// sinkron).
  Future<void> _muat() async {
    final nama = await _repo.namaAkun();
    var riwayat = const <ShiftEntry>[];
    var perShift = const <String, List<Expense>>{};
    if (_bolehLihatRiwayat) {
      final semua = await _repoShift.getShiftsWithUser(
        userId: _cakupan.jenis == JenisCakupan.semua ? null : _cakupan.userId,
      );
      final kandidat = semua.where((e) => e.shift.id != _shiftId).toList();
      perShift = await _repo.getExpensesForShifts(
        kandidat.map((e) => e.shift.id).toList(),
      );
      riwayat = riwayatLayakTampil(
        semua: semua,
        perShift: perShift,
        shiftAktifSaya: _shiftId,
      );
    }
    if (!mounted) return;
    setState(() {
      _nama = nama;
      _riwayat = riwayat;
      _perShift = perShift;
    });
  }

  Future<void> _catat() async {
    final sesi = SessionManager.instance.currentSession;
    final shiftId = sesi?.shiftId;
    if (sesi == null || shiftId == null) return;

    // Dialog hanya mengumpulkan isian; DB baru disentuh setelah dialog
    // benar-benar tertutup (stream yang memancar saat dialog masih beranimasi
    // keluar dulu memicu galat _dependents.isEmpty).
    final isian = await tampilkanDialogPengeluaran(
      context,
      subjudul: 'Masukan Pengeluaran shift',
    );
    if (isian == null || !mounted) return;
    try {
      await _repo.addExpense(
        shiftId: shiftId,
        userId: sesi.userId,
        description: isian.keterangan,
        amount: isian.amount,
        category: isian.kategori.kode,
        qty: isian.qty,
      );
      if (mounted) AppToast.success(context, 'Pengeluaran dicatat');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal mencatat: $e');
    }
  }

  void _bukaRekap(String shiftId) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DetailShiftPage(shiftId: shiftId, repo: _repoShift),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final berjalan = _aliranAktif != null;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (berjalan) ..._shiftAktif() else _belumAda(),
            if (_bolehLihatRiwayat) ..._riwayatPengeluaran(),
          ],
        ),
        if (berjalan)
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
  }

  List<Widget> _shiftAktif() => [
    const JudulBagian('Shift Aktif', ukuran: 18),
    const SizedBox(height: 12),
    StreamBuilder<List<Expense>>(
      stream: _aliranAktif,
      builder: (context, snap) {
        final r = ringkasPengeluaran(snap.data ?? const []);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<RingkasanShift?>(
              stream: _aliranShift,
              builder: (context, s) => _kartuTotal(r, s.data?.shift.startAt),
            ),
            const SizedBox(height: 22),
            const JudulBagian('Rincian Pengeluaran', ukuran: 18),
            const SizedBox(height: 12),
            if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (r.kosong)
              const _TeksKosong('Belum ada pengeluaran di shift ini')
            else
              for (final h in r.perHari) ...[
                KelompokHariPengeluaran(
                  hari: h,
                  repo: _repo,
                  nama: _nama,
                  tampilkanPencatat: false,
                ),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    ),
  ];

  Widget _kartuTotal(RingkasanPengeluaran r, DateTime? mulai) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243C230A),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Pengeluaran Shift ini',
                      style: TextStyle(
                        fontSize: 15,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatRp(r.total),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: WarnaTeras.merah,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: WarnaTeras.oranyeLembut,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${r.jumlahItem} Transaksi',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFF0A94E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Waktu Shift',
                    style: TextStyle(fontSize: 15, color: WarnaTeras.teksPudar),
                  ),
                  const SizedBox(height: 10),
                  if (mulai != null) ...[
                    Text(
                      '${DateFormat('EEEE', 'id_ID').format(mulai)},',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    Text(
                      DateFormat('d MMM yyyy', 'id_ID').format(mulai),
                      style: const TextStyle(
                        fontSize: 13,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: WarnaTeras.garis),
          const SizedBox(height: 10),
          _Tautan(
            'Cek Rekapitulasi Shift',
            ukuran: 13,
            onTap: () => _bukaRekap(_shiftId!),
          ),
        ],
      ),
    );
  }

  Widget _belumAda() {
    return StreamBuilder<RingkasanShift?>(
      stream: _aliranShift,
      builder: (context, snap) => KartuTeras(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF1ECE7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 26,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada pengeluaran',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Shift sudah ditutup dan data pengeluaran direset. Buka shift '
              'baru dari halaman Profil untuk mencatat pengeluaran.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: WarnaTeras.teksPudar,
              ),
            ),
            if (snap.data != null) ...[
              const SizedBox(height: 14),
              _Tautan(
                'Lihat rekap shift terakhir',
                onTap: () => _bukaRekap(snap.data!.shift.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _riwayatPengeluaran() => [
    const SizedBox(height: 22),
    const JudulBagian('Riwayat Pengeluaran', ukuran: 18),
    const SizedBox(height: 12),
    if (_riwayat.isEmpty)
      const _TeksKosong('Belum ada pengeluaran di shift sebelumnya')
    else
      KartuTeras(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < _riwayat.length; i++)
              _kartuRiwayat(_riwayat[i], pertama: i == 0),
          ],
        ),
      ),
  ];
}

extension on _ExpensesPageState {
  Widget _kartuRiwayat(ShiftEntry entri, {required bool pertama}) {
    final semua = _perShift[entri.shift.id] ?? const <Expense>[];
    final aktif = semua.where((e) => e.deletedAt == null);
    return KartuShiftLipat(
      key: ValueKey(entri.shift.id),
      mulai: entri.shift.startAt,
      selesai: entri.shift.endAt,
      pertama: pertama,
      keterangan: [
        '${aktif.length} transaksi',
        if (entri.shift.endAt == null) 'berlangsung',
        if (_cakupan.jenis == JenisCakupan.semua) entri.username,
      ].join(' · '),
      total: '-${formatRp(aktif.fold<int>(0, (s, e) => s + e.amount))}',
      warnaTotal: WarnaTeras.merah,
      isi: () => [
        for (final e in semua)
          BarisPengeluaran(
            pengeluaran: e,
            namaPembatal: e.namaPembatal(_nama),
            onBatalkan: _repo.bolehDibatalkan(e)
                ? () => batalkanPengeluaranLewatDialog(context, _repo, e)
                : null,
          ),
      ],
    );
  }
}

class _TeksKosong extends StatelessWidget {
  final String teks;

  const _TeksKosong(this.teks);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        teks,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, color: WarnaTeras.teksPudar),
      ),
    );
  }
}

/// Tautan oranye kecil berpanah, mis. "Cek Rekapitulasi Shift ›".
class _Tautan extends StatelessWidget {
  final String teks;
  final double ukuran;
  final VoidCallback onTap;

  const _Tautan(this.teks, {required this.onTap, this.ukuran = 13});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              teks,
              style: TextStyle(
                fontSize: ukuran,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: ukuran + 4,
            color: WarnaTeras.oranye,
          ),
        ],
      ),
    );
  }
}
