import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/ui/galat_muat.dart';
import '../../../data/nama_tercatat.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
import '../../../shared/auth/cakupan_riwayat.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/chip_status.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/tab_geser.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../../expenses/widgets/baris_pengeluaran.dart';
import '../../history/widgets/baris_transaksi.dart';
import '../../history/widgets/batalkan_transaksi.dart';
import '../../sales/repositories/sales_repository.dart';
import '../models/ringkasan_shift.dart';
import '../repositories/shift_repository.dart';
import '../../../shared/ui/inisial_akun.dart';

/// Detail Shift (desain): kartu ringkasan · tab Transaksi/Pengeluaran.
///
/// Yang dibatalkan ikut tampil (pudar, dicoret) tapi tidak dihitung.
/// Tab-nya hanya untuk yang boleh melihat isi shift itu
/// ([CakupanRiwayat.bolehLihatIsiShift]); selain itu cukup kartu ringkasan.
/// Baris "Cash / QRIS" di desain sengaja tidak dipakai (keputusan owner):
/// jumlahnya sudah terlihat di baris Cash Total dan QRIS Total.
class DetailShiftPage extends StatefulWidget {
  final String shiftId;

  /// Diisi test; aplikasi memakai basis data utama.
  final ShiftRepository? repo;

  const DetailShiftPage({super.key, required this.shiftId, this.repo});

  @override
  State<DetailShiftPage> createState() => _DetailShiftPageState();
}

class _DetailShiftPageState extends State<DetailShiftPage> {
  late final _repo = widget.repo ?? ShiftRepository(db);
  late final _sales = SalesRepository(db);
  late var _aliran = _repo.watchShift(widget.shiftId);
  // Dibaca ulang tiap sesi berubah: izin dicabut selagi halaman terbuka,
  // daftar transaksi & pengeluaran shift lama langsung tertutup (review C2).
  var _cakupan = CakupanRiwayat.dariSesi();
  Map<String, String> _nama = const {};

  /// 0 = Transaksi, 1 = Pengeluaran.
  var _tab = 0;

  StreamSubscription<Map<String, String>>? _langgananNama;

  @override
  void initState() {
    super.initState();
    // Ikut berubah saat sinkron membawa akun/nama baru (QA kedua K7).
    _langgananNama = _repo.watchNamaAkun().listen((m) {
      if (mounted) setState(() => _nama = m);
    });
    SessionManager.instance.sesiBerubah.addListener(_sesiBerubah);
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    _langgananNama?.cancel();
    super.dispose();
  }

  void _sesiBerubah() {
    final baru = CakupanRiwayat.dariSesi();
    if (mounted && baru != _cakupan) setState(() => _cakupan = baru);
  }

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Detail Shift',
      child: StreamBuilder<RingkasanShift?>(
        stream: _aliran,
        builder: (context, snap) {
          // Dulu terbaca "Shift tidak ditemukan".
          if (snap.hasError) {
            return Center(
              child: GalatMuat(
                galat: snap.error!,
                awalan: 'Detail shift gagal dimuat',
                onCobaLagi: () => setState(
                  () => _aliran = _repo.watchShift(widget.shiftId),
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data;
          if (r == null) {
            return const Center(
              child: Text(
                'Shift tidak ditemukan',
                style: TextStyle(
                  fontSize: TeksTeras.biasa,
                  color: WarnaTeras.teksPudar,
                ),
              ),
            );
          }
          final tujuan = r.shift.digabungKe;
          if (tujuan != null) return _sudahDigabung(r, tujuan);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _kartu(r),
              const SizedBox(height: 18),
              if (!_cakupan.bolehLihatIsiShift(r.shift))
                _kosong(
                  'Daftar transaksi dan pengeluaran shift yang sudah selesai '
                  'butuh izin Lihat Riwayat Lengkap.',
                )
              else ...[
                TabGeser(
                  pilihan: [
                    'Transaksi (${r.transaksi.length})',
                    'Pengeluaran (${r.pengeluaran.length})',
                  ],
                  terpilih: _tab,
                  onPilih: (i) => setState(() => _tab = i),
                  latar: const Color(0xFFEFE6DC),
                  tinggi: 42,
                  sudut: 12,
                ),
                const SizedBox(height: 12),
                if (_tab == 0)
                  ..._daftarTransaksi(r)
                else
                  ..._daftarPengeluaran(r),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Shift ini sudah digabung server ke shift lain akun yang sama (dua HP
  /// membuka shift bersamaan). Datanya tetap disimpan sebagai penanda —
  /// HP yang masih offline butuh petunjuk ke mana transaksinya pindah —
  /// tapi isinya kosong. Dulu tampil "Aktif" dengan Rp0 (audit 6 Nov
  /// nomor 50).
  Widget _sudahDigabung(RingkasanShift r, String tujuan) {
    final nama = r.namaKasir ?? 'kasir ini';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        KartuTeras(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.merge_rounded, color: WarnaTeras.oranye),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shift ini sudah digabung',
                      style: TextStyle(
                        fontSize: TeksTeras.menu,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$nama membuka shift di dua HP bersamaan, jadi keduanya '
                'digabung jadi satu. Semua transaksi dan pengeluarannya '
                'sekarang ada di shift tujuan.',
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  color: WarnaTeras.teksPudar,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DetailShiftPage(shiftId: tujuan, repo: widget.repo),
                    ),
                  ),
                  child: const Text('Lihat shift tujuan'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kartu(RingkasanShift r) {
    final nama = r.namaKasir ?? 'Tanpa nama';
    final durasi = durasiShift(r.shift, DateTime.now());
    return KartuTeras(
      child: Column(
        children: [
          Row(
            children: [
              InisialKasir(nama: nama, ukuran: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TeksTeras.judulBagian,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat(
                        'EEEE, d MMM yyyy',
                        'id_ID',
                      ).format(r.shift.startAt.toLocal()),
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  ],
                ),
              ),
              ChipStatus(label: r.aktif ? 'Aktif' : 'Selesai', aktif: r.aktif),
            ],
          ),
          const GarisTeras(),
          _baris('Waktu', jamShift(r.shift)),
          _baris('Durasi', r.aktif ? '$durasi (berjalan)' : durasi),
          const GarisTeras(),
          _baris(
            'Pendapatan',
            formatRp(r.pendapatan),
            warna: WarnaTeras.oranye,
            besar: true,
          ),
          _baris('Jumlah transaksi', '${r.jumlahTransaksi}'),
          _baris(
            'Dine In / Delivery',
            '${r.jumlahDineIn} / ${r.jumlahDelivery} transaksi',
          ),
          _rincian(r.rincian),
          _baris(
            'Pengeluaran',
            formatRp(r.totalPengeluaran),
            warna: WarnaTeras.merah,
          ),
          _rincian(r.rincianPengeluaran),
          const GarisTeras(),
          _uangKas(r),
        ],
      ),
    );
  }

  /// "Uang kas" (desain): kas awal, lalu kas di laci (shift berjalan) atau
  /// kas akhir (selesai). Shift lama tanpa kas awal: "–".
  Widget _uangKas(RingkasanShift r) {
    final awal = r.shift.kasAwal;
    final akhir = r.kasAkhir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'Uang kas',
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5E5650),
            ),
          ),
        ),
        _baris(
          'Kas awal',
          awal == null ? '–' : formatRp(awal),
          warna: WarnaTeras.hijau,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  r.aktif ? 'Kas di laci saat ini' : 'Kas akhir',
                  style: const TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5E5650),
                  ),
                ),
              ),
              Text(
                akhir == null ? '–' : formatRp(akhir),
                style: TextStyle(
                  fontSize: TeksTeras.angka,
                  fontWeight: FontWeight.w700,
                  // Minus = pengeluaran memakai uang di luar laci.
                  color: (akhir ?? 0) < 0 ? WarnaTeras.merah : WarnaTeras.teks,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Satu baris label kiri · nilai kanan (jarak 9 seperti desain).
  Widget _baris(
    String label,
    String nilai, {
    Color warna = WarnaTeras.teks,
    bool besar = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      // Nilai boleh turun baris kalau melebihi 65% lebar: "3 hari 7 jam
      // (berjalan)" atau jam yang menulis tanggal tidak muat di HP kecil.
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  color: WarnaTeras.teksPudar,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.65),
              child: Text(
                nilai,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: besar ? TeksTeras.angka : TeksTeras.biasa,
                  fontWeight: besar ? FontWeight.w700 : FontWeight.w600,
                  color: warna,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kotak krem: Cash/QRIS × Dine In/Delivery (desain) dan kategori pengeluaran.
  Widget _rincian(List<BarisRincian> isi) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < isi.length; i++)
            _barisRincian(isi[i], terakhir: i == isi.length - 1),
        ],
      ),
    );
  }

  Widget _barisRincian(BarisRincian b, {required bool terakhir}) {
    final kosong = b.jumlah == 0 && !b.tebal;
    final warna = kosong ? WarnaTeras.teksSamar : WarnaTeras.teks;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: terakhir
            ? null
            : Border(
                bottom: BorderSide(
                  color: b.tebal ? const Color(0xFFE2D9D0) : WarnaTeras.garis,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              b.label,
              style: TextStyle(
                fontSize: TeksTeras.kecil,
                fontWeight: b.tebal ? FontWeight.w700 : FontWeight.w400,
                color: b.tebal ? WarnaTeras.teks : const Color(0xFF5E5650),
              ),
            ),
          ),
          Text(
            '${b.jumlah} ${b.satuan}',
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88),
            child: Text(
              formatRp(b.total),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: TeksTeras.kecil,
                fontWeight: FontWeight.w700,
                color: warna,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _daftarTransaksi(RingkasanShift r) {
    if (r.transaksi.isEmpty) {
      return [_kosong('Belum ada transaksi di shift ini')];
    }
    return [
      for (final t in r.transaksi)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: BarisTransaksiShift(
            transaksi: t,
            namaPembatal: t.namaPembatal(_nama),
            setelahTutup: r.masukSetelahTutup(t.createdAt),
            onTap: () => bukaDetailTransaksi(context, _sales, t),
          ),
        ),
    ];
  }

  List<Widget> _daftarPengeluaran(RingkasanShift r) {
    if (r.pengeluaran.isEmpty) {
      return [_kosong('Tidak ada pengeluaran di shift ini')];
    }
    return [
      for (final e in r.pengeluaran)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: WarnaTeras.kartu,
            borderRadius: BorderRadius.circular(12),
          ),
          child: BarisPengeluaran(
            pengeluaran: e,
            namaPembatal: e.namaPembatal(_nama),
            ruangTombol: false,
            setelahTutup: r.masukSetelahTutup(e.createdAt),
          ),
        ),
    ];
  }

  Widget _kosong(String teks) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text(
      teks,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: TeksTeras.biasa,
        color: WarnaTeras.teksPudar,
      ),
    ),
  );
}
