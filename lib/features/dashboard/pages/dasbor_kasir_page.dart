import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/baris_angka.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/kepala_sapaan.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/currency_formatter.dart';
import '../../products/widgets/baris_produk.dart';
import '../../sales/models/keranjang.dart';
import '../../sales/models/pilihan_produk.dart';
import '../../sales/sheets/pilihan_produk_sheet.dart';
import '../../shift/aksi_shift.dart';
import '../../shift/models/format_shift.dart';
import '../../shift/models/produk_laris.dart';
import '../../shift/models/ringkasan_shift.dart';
import '../../shift/repositories/shift_repository.dart';
import '../widgets/kisi_produk_laris.dart';

/// Dashboard KASIR (desain): kartu shift berjalan atau "Shift selesai",
/// lalu Produk Paling Laris minggu ini. Owner memakai `DasborOwnerPage`.
class DasborKasirPage extends StatefulWidget {
  /// Keranjang bersama halaman Kasir — produk laris yang diketuk masuk ke
  /// sini.
  final Keranjang keranjang;

  /// Diisi test; aplikasi memakai basis data utama.
  final ShiftRepository? repo;

  const DasborKasirPage({super.key, required this.keranjang, this.repo});

  @override
  State<DasborKasirPage> createState() => _DasborKasirPageState();
}

class _DasborKasirPageState extends State<DasborKasirPage> {
  late final _repo = widget.repo ?? ShiftRepository(db);
  late final Timer _tiapMenit;

  // Aliran dibuat ulang hanya kalau kuncinya berubah — membuatnya di setiap
  // build membuat StreamBuilder mulai dari kosong dan layar berkedip.
  String? _kunciShift;
  Stream<RingkasanShift?>? _aliranShift;
  DateTime? _minggu;
  Stream<List<ProdukLaris>>? _aliranLaris;
  String? _kunciTerlaris;
  Stream<List<ProdukLaris>>? _aliranTerlaris;

  @override
  void initState() {
    super.initState();
    SessionManager.instance.sesiBerubah.addListener(_segarkan);
    // Lama shift bertambah dan minggu bisa berganti walau tidak ada transaksi.
    _tiapMenit = Timer.periodic(const Duration(minutes: 1), (_) => _segarkan());
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_segarkan);
    _tiapMenit.cancel();
    super.dispose();
  }

  void _segarkan() {
    if (mounted) setState(() {});
  }

  Stream<RingkasanShift?> _shift(String userId, String? shiftId) {
    final kunci = '$userId|$shiftId';
    if (kunci != _kunciShift) {
      _kunciShift = kunci;
      _aliranShift = shiftId != null
          ? _repo.watchShift(shiftId)
          : _repo.watchShiftTerakhirSelesai(userId);
    }
    return _aliranShift!;
  }

  Stream<List<ProdukLaris>> _laris(DateTime sekarang) {
    final minggu = awalMinggu(sekarang);
    if (minggu != _minggu) {
      _minggu = minggu;
      _aliranLaris = _repo.watchProdukLarisMinggu(minggu);
    }
    return _aliranLaris!;
  }

  Stream<List<ProdukLaris>> _terlaris(String shiftId) {
    if (shiftId != _kunciTerlaris) {
      _kunciTerlaris = shiftId;
      _aliranTerlaris = _repo.watchTerlarisShift(shiftId);
    }
    return _aliranTerlaris!;
  }

  Future<void> _pilihProduk(ProdukLaris laris) async {
    final p = laris.produk;
    if (p == null) return;
    if (SessionManager.instance.currentSession?.shiftId == null) {
      AppToast.info(context, 'Buka shift dulu untuk mulai berjualan');
      return;
    }
    String? catatan;
    if (kelompokUntuk(p).isNotEmpty) {
      catatan = await tanyaPilihanProduk(context, p);
      if (catatan == null || !mounted) return; // lembar ditutup = batal
    }
    widget.keranjang.tambah(
      idProduk: p.id,
      nama: p.name,
      harga: p.price,
      catatan: catatan == null ? null : catatanItem(catatan),
    );
    AppToast.success(context, '${p.name} ditambahkan ke keranjang');
  }

  @override
  Widget build(BuildContext context) {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) return const SizedBox.shrink();
    final sekarang = DateTime.now();
    final berjalan = sesi.shiftId != null;

    return StreamBuilder<RingkasanShift?>(
      stream: _shift(sesi.userId, sesi.shiftId),
      builder: (context, snap) {
        final r = snap.data;
        final siap = snap.connectionState != ConnectionState.waiting;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (!siap)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (berjalan)
              _kartuBerjalan(sesi.username, r, sekarang)
            else
              _kartuSelesai(sesi.username, r, sekarang),
            if (siap && !berjalan && r != null)
              _terlarisShiftTerakhir(r, sekarang),
            StreamBuilder<List<ProdukLaris>>(
              stream: _laris(sekarang),
              builder: (context, snap) => snap.hasData
                  ? KisiProdukLaris(daftar: snap.data!, onPilih: _pilihProduk)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _kartuBerjalan(String nama, RingkasanShift? r, DateTime sekarang) {
    final mulai = r?.shift.startAt ?? sekarang;
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KepalaSapaan(
            nama: nama,
            ikon: Icons.person_rounded,
            lencana: LencanaSapaan(
              lamaShift(mulai, sekarang),
              ikon: Icons.schedule_rounded,
            ),
          ),
          const GarisTeras(),
          BarisAngka(
            isi: [
              Angka('Mulai', DateFormat('HH:mm').format(mulai)),
              Angka('Transaksi', '${r?.jumlahTransaksi ?? 0}'),
              Angka(
                'Pendapatan Shift',
                formatRp(r?.pendapatan ?? 0),
                warna: WarnaTeras.oranye,
                lebar: 3,
              ),
            ],
          ),
          const GarisTeras(),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _metode(
                Icons.payments_rounded,
                WarnaTeras.hijau,
                'Tunai: ${r?.jumlahTunai ?? 0} transaksi',
              ),
              _metode(
                Icons.qr_code_2_rounded,
                WarnaTeras.biru,
                'QRIS: ${r?.jumlahQris ?? 0} transaksi',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kotakUang(
                  Icons.account_balance_wallet_rounded,
                  'Kas awal',
                  r?.shift.kasAwal == null ? '–' : formatRp(r!.shift.kasAwal!),
                  WarnaTeras.hijau,
                  const Color(0xFFF3FAF4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kotakUang(
                  Icons.receipt_long_rounded,
                  'Pengeluaran',
                  formatRp(r?.totalPengeluaran ?? 0),
                  WarnaTeras.merah,
                  const Color(0xFFFDF1EF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kartuSelesai(String nama, RingkasanShift? r, DateTime sekarang) {
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KepalaSapaan(
            nama: nama,
            ikon: Icons.person_rounded,
            latarIkon: const Color(0xFFF1ECE7),
            warnaIkon: WarnaTeras.teksPudar,
            lencana: r == null
                ? const LencanaSapaan(
                    'Belum buka shift',
                    latar: Color(0xFFF1ECE7),
                    warna: WarnaTeras.teksPudar,
                  )
                : const LencanaSapaan(
                    'Shift selesai',
                    ikon: Icons.check_circle_rounded,
                    latar: Color(0xFFEAF5EC),
                    warna: WarnaTeras.hijau,
                  ),
          ),
          const GarisTeras(),
          if (r == null)
            const Text(
              'Belum ada shift sebelumnya. Buka shift untuk mulai berjualan.',
              style: TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
            )
          else ...[
            Text(
              'Ringkasan shift terakhir · '
              '${rentangShift(r.shift.startAt, r.shift.endAt, sekarang)}',
              style: const TextStyle(
                fontSize: TeksTeras.keterangan,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 8),
            BarisAngka(
              isi: [
                Angka(
                  'Transaksi',
                  '${r.jumlahTransaksi}',
                  warna: const Color(0xFF5A5048),
                ),
                Angka(
                  'Pendapatan Shift',
                  formatRp(r.pendapatan),
                  warna: const Color(0xFF5A5048),
                  lebar: 3,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TombolLembar(
            label: r == null ? 'Buka Shift' : 'Buka Shift Baru',
            ikon: Icons.play_arrow_rounded,
            latar: WarnaTeras.oranye,
            warna: Colors.white,
            tinggi: 46,
            sudut: 12,
            onPressed: () => bukaShiftLewatDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _terlarisShiftTerakhir(RingkasanShift r, DateTime sekarang) {
    return StreamBuilder<List<ProdukLaris>>(
      stream: _terlaris(r.shift.id),
      builder: (context, snap) {
        final daftar = snap.data ?? const <ProdukLaris>[];
        if (daftar.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JudulDasbor(
              'Terlaris di Shift Terakhir',
              keterangan:
                  'Penjualan selama shift '
                  '${rentangShift(r.shift.startAt, r.shift.endAt, sekarang)}',
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: WarnaTeras.kartu,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < daftar.length; i++)
                    _barisPeringkat(i + 1, daftar[i], pertama: i == 0),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _barisPeringkat(
    int peringkat,
    ProdukLaris p, {
    required bool pertama,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: pertama
          ? null
          : const BoxDecoration(
              border: Border(top: BorderSide(color: WarnaTeras.garis)),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$peringkat',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: peringkat == 1
                    ? WarnaTeras.oranye
                    : WarnaTeras.teksPudar,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FotoProduk(path: p.foto, ukuran: 40, sudut: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.nama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WarnaTeras.teks,
              ),
            ),
          ),
          Text(
            '${p.terjual} terjual',
            style: const TextStyle(fontSize: 12, color: Color(0xFF5A5048)),
          ),
        ],
      ),
    );
  }

  Widget _metode(IconData ikon, Color warna, String teks) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikon, size: 18, color: warna),
        const SizedBox(width: 6),
        Text(
          teks,
          style: const TextStyle(fontSize: 12, color: WarnaTeras.teks),
        ),
      ],
    );
  }

  Widget _kotakUang(
    IconData ikon,
    String label,
    String nilai,
    Color warna,
    Color latar,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 16, color: warna),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5E5650),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              nilai,
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w700,
                color: warna,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
