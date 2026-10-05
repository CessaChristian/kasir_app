import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
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
import '../widgets/kartu_shift.dart';

/// Detail Shift (desain): kartu ringkasan · tab Transaksi/Pengeluaran.
///
/// Yang dibatalkan ikut tampil (pudar, dicoret) tapi tidak dihitung. Bagian
/// "Uang kas" (kas awal, kas di laci/kas akhir) menyusul bersama fitur kas
/// awal di fase kasir.
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
  late final _aliran = _repo.watchShift(widget.shiftId);
  Map<String, String> _nama = const {};

  /// 0 = Transaksi, 1 = Pengeluaran.
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    _repo.namaAkun().then((m) {
      if (mounted) setState(() => _nama = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Detail Shift',
      child: StreamBuilder<RingkasanShift?>(
        stream: _aliran,
        builder: (context, snap) {
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _kartu(r),
              const SizedBox(height: 18),
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
          );
        },
      ),
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
          _baris('Cash / QRIS', '${r.jumlahTunai} / ${r.jumlahQris} transaksi'),
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
        ],
      ),
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
      child: Row(
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
          Text(
            nilai,
            style: TextStyle(
              fontSize: besar ? TeksTeras.angka : TeksTeras.biasa,
              fontWeight: besar ? FontWeight.w700 : FontWeight.w600,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  /// Kotak krem Cash/QRIS × Dine In/Delivery (desain).
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
            '${b.jumlah} trx',
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
            namaPembatal: _nama[t.cancelledByUserId],
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
            namaPembatal: _nama[e.cancelledByUserId],
            ruangTombol: false,
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
