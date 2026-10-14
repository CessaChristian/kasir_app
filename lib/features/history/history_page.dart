import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../shared/auth/cakupan_riwayat.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/ui/kartu_teras.dart';
import '../../shared/ui/kotak_cari.dart';
import '../../shared/ui/warna_teras.dart';
import '../sales/repositories/sales_repository.dart';
import '../shift/models/ringkasan_shift.dart';
import '../shift/pages/detail_shift_page.dart';
import '../shift/repositories/shift_repository.dart';
import 'models/kelompok_riwayat.dart';
import 'widgets/daftar_hari_riwayat.dart';

/// Halaman Riwayat KASIR (desain): cari · chip Semua/Tunai/QRIS · transaksi
/// per hari berpita oranye yang bisa dilipat — bentuk yang sama dengan
/// Riwayat owner.
///
/// Isinya mengikuti `CakupanRiwayat`: tanpa izin Lihat Riwayat Lengkap hanya
/// shift yang sedang berjalan; dengan izin itu semua transaksi miliknya
/// (keputusan owner 2026-10-13). Tidak ada yang bisa dilihat → kartu "Belum
/// ada transaksi". Owner memakai `RiwayatOwnerPage`.
class HistoryPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final SalesRepository? repo;
  final ShiftRepository? repoShift;

  const HistoryPage({super.key, this.repo, this.repoShift});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final _repo = widget.repo ?? SalesRepository(db);
  late final _repoShift = widget.repoShift ?? ShiftRepository(db);

  // Dibuat sekali: cakupannya ditentukan sesi saat halaman dibuka, dan stream
  // yang dibuat ulang tiap build membuat daftarnya berkedip.
  final _cakupan = CakupanRiwayat.dariSesi();
  late final _riwayat = _repo.watchRiwayat(_cakupan);
  late final Stream<RingkasanShift?>? _aliranRekap;

  /// Kode metode bayar ('cash'/'qris'); null = Semua.
  String? _metode;
  var _cari = '';
  Set<String> _idCocokMenu = const {};
  Map<String, String> _nama = const {};

  /// Hari yang dilipat. Kosong = semua terbuka (desain).
  final _terlipat = <DateTime>{};

  @override
  void initState() {
    super.initState();
    final sesi = SessionManager.instance.currentSession;
    _aliranRekap = sesi == null
        ? null
        : _repoShift.watchShiftTerakhirSelesai(sesi.userId);
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
        final semua = snap.data;
        final hari = semua == null
            ? null
            : kelompokkanRiwayat(
                semua,
                periode: null,
                metode: _metode,
                cari: _cari,
                idCocokMenu: _idCocokMenu,
              );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KotakCari(
              petunjuk: 'Cari riwayat...',
              besar: true,
              onBerubah: _ubahCari,
            ),
            const SizedBox(height: 16),
            _chipMetode(),
            const SizedBox(height: 16),
            if (hari == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (semua!.isEmpty)
              _belumAda()
            else if (hari.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Riwayat tidak ditemukan',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: WarnaTeras.teksPudar),
                ),
              )
            else
              DaftarHariRiwayat(
                hari: hari,
                repo: _repo,
                nama: _nama,
                terlipat: _terlipat,
                onLipat: (h) => setState(() {
                  if (!_terlipat.remove(h)) _terlipat.add(h);
                }),
              ),
          ],
        );
      },
    );
  }

  Widget _chipMetode() {
    Widget chip(String label, String? kode) {
      final dipilih = _metode == kode;
      return Material(
        color: dipilih ? WarnaTeras.oranye : WarnaTeras.kartu,
        elevation: dipilih ? 0 : 1,
        shadowColor: const Color(0x14000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: dipilih ? WarnaTeras.oranye : const Color(0xFFE6DED6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => setState(() => _metode = kode),
          child: SizedBox(
            width: 84,
            height: 34,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: dipilih ? Colors.white : WarnaTeras.teks,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      spacing: 10,
      children: [
        chip('Semua', null),
        chip('Tunai', 'cash'),
        chip('QRIS', 'qris'),
      ],
    );
  }

  Widget _belumAda() {
    final berjalan = SessionManager.instance.currentSession?.shiftId != null;
    return StreamBuilder<RingkasanShift?>(
      stream: _aliranRekap,
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
                Icons.receipt_long_rounded,
                size: 26,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada transaksi',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              berjalan
                  ? 'Transaksi di shift ini akan muncul di sini.'
                  : 'Shift sudah ditutup dan riwayat transaksi direset. Buka '
                        'shift baru dari halaman Profil untuk mulai mencatat '
                        'transaksi.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: WarnaTeras.teksPudar,
              ),
            ),
            if (!berjalan && snap.data != null) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailShiftPage(
                      shiftId: snap.data!.shift.id,
                      repo: _repoShift,
                    ),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Lihat rekap shift terakhir',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: WarnaTeras.oranye,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
