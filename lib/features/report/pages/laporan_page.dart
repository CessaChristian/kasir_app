import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/services/simpan_berkas.dart';
import '../../../shared/constants/category_icons.dart';
import '../../../shared/ui/bar_segmen.dart';
import '../../../shared/ui/judul_bagian.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/periode/kartu_periode.dart';
import '../../../shared/ui/periode/periode.dart';
import '../../../shared/ui/tab_geser.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/currency_formatter.dart';
import '../../expenses/models/kategori_biaya.dart';
import '../../products/widgets/baris_produk.dart';
import '../models/ringkasan_laporan.dart';
import '../repositories/laporan_repository.dart';
import '../services/dokumen_laporan.dart';
import '../services/ekspor_laporan.dart';
import '../services/pdf_laporan.dart';
import '../widgets/lembar_unduh_laporan.dart';
import '../widgets/grafik_batang.dart';
import '../widgets/kartu_dibatalkan.dart';

/// Laporan (desain): periode · unduh · pendapatan · yang dibatalkan · tren ·
/// metode bayar · tipe pesanan · per kategori · per produk.
///
/// Dipakai owner (dari Profil) dan kasir yang punya izin `view_report`.
/// Pengeluaran hanya tampil untuk yang boleh melihatnya
/// (`view_all_expenses`, owner selalu boleh).
class LaporanPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final LaporanRepository? repo;

  const LaporanPage({super.key, this.repo});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  late final _repo = widget.repo ?? LaporanRepository(db);
  var _periode = Periode.hari(DateTime.now());
  late Stream<RingkasanLaporan> _aliran = _repo.watchLaporan(_periode);
  Map<String, String> _nama = const {};

  /// Urutan per produk: true = Terjual, false = Pendapatan.
  var _urutTerjual = false;
  var _semuaProduk = false;

  /// Batang Tren Pendapatan yang diketuk (gelembung nominal); null = tidak
  /// ada. Direset saat periode berganti, karena batangnya ikut berganti.
  int? _batangTerpilih;
  var _mengekspor = false;

  static const _produkAwal = 5;

  bool get _lihatPengeluaran =>
      SessionManager.instance.hasPermission('view_all_expenses');

  @override
  void initState() {
    super.initState();
    _repo.namaAkun().then((m) {
      if (mounted) setState(() => _nama = m);
    });
  }

  void _ubahPeriode(Periode p) => setState(() {
    _periode = p;
    _batangTerpilih = null;
    _aliran = _repo.watchLaporan(p);
  });

  /// Alur unduh (desain): pilih format → file dibuat → "Laporan siap" →
  /// Simpan ke HP atau Bagikan.
  Future<void> _unduh(RingkasanLaporan r) async {
    if (!r.adaIsi(denganPengeluaran: _lihatPengeluaran)) {
      AppToast.warning(context, 'Tidak ada data untuk diunduh di periode ini');
      return;
    }
    final format = await pilihFormatLaporan(
      context,
      labelPeriode: labelPeriodeUnduhan(_periode),
    );
    if (format == null || !mounted) return;

    setState(() => _mengekspor = true);
    final DokumenLaporan dok;
    final Uint8List bita;
    try {
      dok = susunDokumenLaporan(
        namaToko: AppConstants.storeName,
        periode: _periode,
        r: r,
        nama: _nama,
        denganPengeluaran: _lihatPengeluaran,
        dibuat: DateTime.now(),
        olehNama: SessionManager.instance.currentSession?.username ?? '-',
      );
      // Di isolate terpisah: laporan besar butuh beberapa detik, layar
      // tidak boleh membeku selama itu.
      bita = switch (format) {
        FormatLaporan.pdf => await buatPdfLaporanDiLatar(
          dok,
          await BahanPdf.muat(),
        ),
        FormatLaporan.excel => await buatExcelLaporanDiLatar(dok),
      };
    } catch (e, jejak) {
      debugPrint('Gagal membuat laporan: $e\n$jejak');
      if (mounted) {
        AppToast.error(
          context,
          'Gagal membuat laporan. Coba lagi, atau pilih periode yang lebih '
          'pendek.',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _mengekspor = false);
    }
    if (!mounted) return;

    final namaFile = '${dok.namaFile}.${format.ekstensi}';
    final cara = await tampilkanLaporanSiap(
      context,
      format: format,
      namaFile: namaFile,
      keterangan: 'Periode ${dok.labelPeriode} · ${ukuranBerkas(bita.length)}',
    );
    if (cara == null || !mounted) return;
    try {
      switch (cara) {
        case CaraSimpan.simpanKeHp:
          await SimpanBerkas.keDownload(
            nama: namaFile,
            mime: format.mime,
            bita: bita,
          );
          if (mounted) {
            AppToast.success(context, 'Laporan tersimpan di folder Download');
          }
        case CaraSimpan.bagikan:
          await SimpanBerkas.bagikan(
            nama: namaFile,
            mime: format.mime,
            bita: bita,
            subjek: 'Laporan ${AppConstants.storeName} ${dok.labelPeriode}',
          );
      }
    } on BerkasTidakTersimpan catch (e) {
      if (mounted) AppToast.error(context, e.pesan);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Gagal membagikan laporan: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RingkasanLaporan>(
      stream: _aliran,
      builder: (context, snap) {
        final r = snap.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KartuPeriode(periode: _periode, onBerubah: _ubahPeriode),
            const SizedBox(height: 14),
            if (r == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _tombolUnduh(r),
              const SizedBox(height: 12),
              _pendapatan(r),
              _judul('Transaksi Dibatalkan'),
              _transaksiBatal(r),
              if (_lihatPengeluaran) ...[
                _judul('Pengeluaran Dibatalkan'),
                _pengeluaranBatal(r),
              ],
              _judul('Tren Pendapatan'),
              _tren(r),
              _judul('Metode Pembayaran'),
              _metode(r),
              _judul('Tipe Pesanan'),
              _tipe(r),
              _judul('Pendapatan per Kategori'),
              _kategori(r),
              _judulProduk(),
              _produk(r),
            ],
          ],
        );
      },
    );
  }

  Widget _judul(String teks) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: JudulBagian(teks),
  );

  Widget _tombolUnduh(RingkasanLaporan r) {
    return Opacity(
      opacity: _mengekspor ? 0.6 : 1,
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _mengekspor ? null : () => _unduh(r),
          style: OutlinedButton.styleFrom(
            foregroundColor: WarnaTeras.oranye,
            backgroundColor: WarnaTeras.kartu,
            disabledForegroundColor: WarnaTeras.oranye,
            side: const BorderSide(color: WarnaTeras.oranye),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: _mengekspor
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: WarnaTeras.oranye,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 20),
          label: Text(
            _mengekspor ? 'Menyiapkan laporan…' : 'Unduh Laporan',
            style: const TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendapatan(RingkasanLaporan r) {
    return KartuTeras(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pendapatan',
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRp(r.pendapatan),
              style: const TextStyle(
                fontSize: TeksTeras.angkaBesar,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${r.jumlahShift} shift · ${r.jumlahHari} hari',
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.teksSamar,
            ),
          ),
          const GarisTeras(),
          Row(
            children: [
              _angka('Transaksi', '${r.jumlahTransaksi}'),
              _angka('Rata-rata / transaksi', formatRp(r.rataRata)),
            ],
          ),
          if (_lihatPengeluaran) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _angka(
                  'Pengeluaran',
                  formatRp(r.pengeluaran),
                  warna: WarnaTeras.merah,
                ),
                _angka(
                  'Laba kotor',
                  formatRp(r.labaKotor),
                  warna: WarnaTeras.hijau,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _angka(String label, String nilai, {Color warna = WarnaTeras.teks}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
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

  Widget _transaksiBatal(RingkasanLaporan r) {
    return KartuDibatalkan(
      ikon: Icons.delete_rounded,
      jumlah: '${r.transaksiBatal.length} transaksi',
      nilai: formatRp(r.nilaiTransaksiBatal),
      kosong: 'Tidak ada transaksi yang dibatalkan pada periode ini.',
      catatan: 'Tidak dihitung dalam pendapatan di atas.',
      isi: [
        for (final t in r.transaksiBatal)
          BarisDibatalkan(
            judul: t.invoiceNo,
            keterangan: [
              DateFormat('dd/MM').format(t.createdAt.toLocal()),
              DateFormat('HH:mm').format(t.deletedAt!.toLocal()),
              'oleh ${_nama[t.cancelledByUserId] ?? '-'}',
            ].join(' · '),
            alasan: t.cancelReason,
            nilai: formatRp(t.total),
          ),
      ],
    );
  }

  Widget _pengeluaranBatal(RingkasanLaporan r) {
    return KartuDibatalkan(
      ikon: Icons.account_balance_wallet_rounded,
      jumlah: '${r.pengeluaranBatal.length} pengeluaran',
      nilai: formatRp(r.nilaiPengeluaranBatal),
      kosong: 'Tidak ada pengeluaran yang dibatalkan pada periode ini.',
      catatan: 'Tidak dihitung dalam pengeluaran di atas.',
      isi: [
        for (final e in r.pengeluaranBatal)
          BarisDibatalkan(
            judul: e.qty > 1 ? '${e.description} (${e.qty}x)' : e.description,
            keterangan: [
              KategoriBiaya.labelDari(e.category),
              DateFormat('HH:mm').format(e.deletedAt!.toLocal()),
              'oleh ${_nama[e.cancelledByUserId] ?? '-'}',
            ].join(' · '),
            alasan: e.cancelReason,
            nilai: formatRp(e.amount),
          ),
      ],
    );
  }

  Widget _tren(RingkasanLaporan r) {
    final puncak = r.grafik.fold(0, (m, b) => b.nilai > m ? b.nilai : m);
    return KartuTeras(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.judulGrafik,
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ),
              Text.rich(
                TextSpan(
                  text: 'Tertinggi ',
                  children: [
                    TextSpan(
                      text: formatRp(puncak),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.teksPudar,
                ),
              ),
            ],
          ),
          // Ruang untuk gelembung nominal di atas batang yang diketuk.
          SizedBox(height: r.tanpaShift ? 14 : 50),
          if (r.tanpaShift)
            const SizedBox(
              height: GrafikBatang.tinggi,
              child: Center(
                child: Text(
                  'Tidak ada shift di hari ini',
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ),
            )
          else
            GrafikBatang(
              batang: r.grafik,
              terpilih: _batangTerpilih,
              onPilih: (i) => setState(() => _batangTerpilih = i),
            ),
        ],
      ),
    );
  }

  static String _persen(int nilai, int total) =>
      '${total == 0 ? 0 : (nilai / total * 100).round()}%';

  Widget _metode(RingkasanLaporan r) {
    final semua = r.jumlahTransaksi;
    Widget satu(
      String label,
      IconData ikon,
      Color latar,
      Color warna,
      Porsi p,
    ) {
      return Expanded(
        child: Row(
          children: [
            _kotakIkon(ikon, latar, warna, 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label · ${_persen(p.jumlah, semua)}',
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatRp(p.nilai),
                      style: const TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ),
                  Text(
                    '${p.jumlah} transaksi',
                    style: const TextStyle(
                      fontSize: TeksTeras.keterangan,
                      color: WarnaTeras.teksSamar,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return KartuTeras(
      child: Column(
        children: [
          BarSegmen(
            isi: [
              (r.tunai.jumlah, WarnaTeras.hijau),
              (r.qris.jumlah, WarnaTeras.biru),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              satu(
                'Tunai',
                Icons.payments_rounded,
                WarnaTeras.hijauMuda,
                WarnaTeras.hijau,
                r.tunai,
              ),
              const SizedBox(width: 10),
              satu(
                'QRIS',
                Icons.qr_code_2_rounded,
                const Color(0xFFE8F0FB),
                WarnaTeras.biru,
                r.qris,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tipe(RingkasanLaporan r) {
    final tipe = [
      (
        'Dine In',
        Icons.restaurant_rounded,
        WarnaTeras.oranye,
        WarnaTeras.oranyeMuda,
        r.dineIn,
      ),
      (
        'Delivery',
        Icons.two_wheeler_rounded,
        WarnaTeras.hijau,
        WarnaTeras.hijauMuda,
        r.delivery,
      ),
    ];
    return KartuTeras(
      child: Column(
        children: [
          BarSegmen(celah: 2, isi: [for (final t in tipe) (t.$5.nilai, t.$3)]),
          for (final (label, ikon, warna, latar, p) in tipe) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _kotakIkon(ikon, latar, warna, 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w600,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      Text(
                        '${p.jumlah} transaksi',
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRp(p.nilai),
                      style: const TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    Text(
                      _persen(p.nilai, r.pendapatan),
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kotakIkon(IconData ikon, Color latar, Color warna, double ukuran) {
    return Container(
      width: ukuran,
      height: ukuran,
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(ukuran * 0.28),
      ),
      child: Icon(ikon, size: ukuran * 0.56, color: warna),
    );
  }

  static const _batangLaporan = Color(0xFFF3A65C);

  Widget _bar(double porsi, double tinggi) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(tinggi / 2),
      child: LinearProgressIndicator(
        value: porsi,
        minHeight: tinggi,
        color: _batangLaporan,
        backgroundColor: WarnaTeras.latarAbu,
      ),
    );
  }

  Widget _kategori(RingkasanLaporan r) {
    final total = r.perKategori.fold(0, (s, k) => s + k.nilai);
    final maks = r.perKategori.fold(0, (m, k) => k.nilai > m ? k.nilai : m);
    return KartuTeras(
      child: Column(
        children: [
          for (var i = 0; i < r.perKategori.length; i++) ...[
            if (i > 0) const SizedBox(height: 11),
            Row(
              children: [
                Icon(
                  r.perKategori[i].ikon == null
                      ? Icons.block_rounded
                      : categoryIconFromCodepoint(r.perKategori[i].ikon),
                  size: 18,
                  color: WarnaTeras.oranye,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.perKategori[i].nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
                Text(
                  _persen(r.perKategori[i].nilai, total),
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 92),
                  child: Text(
                    formatRp(r.perKategori[i].nilai),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: TeksTeras.kecil,
                      fontWeight: FontWeight.w700,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _bar(maks == 0 ? 0 : r.perKategori[i].nilai / maks, 6),
          ],
        ],
      ),
    );
  }

  Widget _judulProduk() {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(
        children: [
          const Expanded(child: JudulBagian('Pendapatan per Produk')),
          SizedBox(
            width: 176,
            child: TabGeser(
              pilihan: const ['Pendapatan', 'Terjual'],
              terpilih: _urutTerjual ? 1 : 0,
              onPilih: (i) => setState(() => _urutTerjual = i == 1),
              latar: const Color(0xFFEFE6DC),
              tinggi: 32,
              sudut: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _produk(RingkasanLaporan r) {
    int kunci(PenjualanProduk p) => _urutTerjual ? p.terjual : p.nilai;
    final urut = [...r.perProduk]
      ..sort((a, b) {
        final c = kunci(b).compareTo(kunci(a));
        if (c != 0) return c;
        final n = b.nilai.compareTo(a.nilai);
        // Nilai sama (mis. sama-sama tidak laku): urut nama, supaya urutannya
        // tidak berubah-ubah setiap dimuat ulang.
        return n != 0 ? n : a.nama.compareTo(b.nama);
      });
    final atas = urut.fold(1, (m, p) => kunci(p) > m ? kunci(p) : m);
    final tampil = _semuaProduk ? urut : urut.take(_produkAwal).toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tampil.length; i++)
            _barisProduk(
              i + 1,
              tampil[i],
              r.pendapatan,
              kunci(tampil[i]) / atas,
            ),
          if (urut.length > _produkAwal)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Material(
                color: WarnaTeras.oranyeMuda,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _semuaProduk = !_semuaProduk),
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _semuaProduk
                                ? 'Tampilkan lebih sedikit'
                                : 'Lihat semua ${urut.length} produk',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: TeksTeras.biasa,
                              fontWeight: FontWeight.w600,
                              color: WarnaTeras.oranye,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _semuaProduk
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                          color: WarnaTeras.oranye,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _barisProduk(
    int peringkat,
    PenjualanProduk p,
    int total,
    double porsi,
  ) {
    return Opacity(
      opacity: p.terjual == 0 ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$peringkat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: TeksTeras.kecil,
                  fontWeight: FontWeight.w700,
                  color: peringkat <= 3 && p.terjual > 0
                      ? WarnaTeras.oranye
                      : WarnaTeras.teksSamar,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FotoProduk(path: p.foto, ukuran: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nama,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TeksTeras.biasa,
                            fontWeight: FontWeight.w600,
                            color: WarnaTeras.teks,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRp(p.nilai),
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.oranye,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.punyaKategori
                              ? '${p.terjual} terjual · ${p.kategori}'
                              : '${p.terjual} terjual',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TeksTeras.kecil,
                            color: WarnaTeras.teksPudar,
                          ),
                        ),
                      ),
                      Text(
                        _persen(p.nilai, total),
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _bar(porsi, 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
