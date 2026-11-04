import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/ui/galat_muat.dart';
import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../shared/ui/pita_hari.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../../sales/repositories/sales_repository.dart';
import '../models/saringan_riwayat.dart';
import 'baris_transaksi.dart';
import 'batalkan_transaksi.dart';

/// Daftar Riwayat per hari (desain): pita oranye "Kamis, 1 Okt 2026 · N
/// Transaksi · total" yang bisa dilipat, berisi baris transaksi dengan tombol
/// batalkan (kalau boleh) dan detail struk. Dipakai Riwayat owner dan kasir.
///
/// ── KENAPA DIBANGUN SEPERTI INI (QA kedua K8) ──
///
/// Dulu seluruh transaksi sepanjang masa dibaca, disaring di aplikasi, dan
/// SEMUA barisnya dibangun sekaligus — terasa berat bahkan dengan data uji.
/// Sekarang:
///   - pita tanggal (jumlah & total) dihitung database, satu baris per hari;
///   - hanya [hariTerbuka] hari teratas yang terbuka (keputusan owner
///     2026-10-30), dan transaksi hanya dibaca untuk hari yang terbuka;
///   - barisnya dibangun selagi digulir (`ListView.builder`).
class DaftarRiwayat extends StatefulWidget {
  final SaringanRiwayat saringan;
  final SalesRepository repo;

  /// Kotak cari, saringan, dsb. — digulir bersama daftar.
  final List<Widget> kepala;

  /// Tampilan kosong. [disaring]: ada saringan dari pemakai, jadi kosongnya
  /// berarti "tidak ditemukan", bukan "belum ada transaksi".
  final Widget Function(bool disaring) kosong;

  final EdgeInsets padding;

  /// Hari teratas yang terbuka saat pertama tampil.
  static const hariTerbuka = 5;

  const DaftarRiwayat({
    super.key,
    required this.saringan,
    required this.repo,
    required this.kepala,
    required this.kosong,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  @override
  State<DaftarRiwayat> createState() => _DaftarRiwayatState();
}

class _DaftarRiwayatState extends State<DaftarRiwayat> {
  late Stream<List<RingkasanHari>> _hari =
      widget.repo.watchHariRiwayat(widget.saringan);
  late final _nama = widget.repo.watchNamaAkun();

  /// Pilihan pemakai per hari (buka/lipat). Hari tanpa pilihan mengikuti
  /// aturan [DaftarRiwayat.hariTerbuka].
  final _pilihan = <DateTime, bool>{};

  Stream<List<Transaction>>? _isi;
  String? _kunciIsi;

  /// Saringan baru dipilih, dan isi untuknya belum datang. Hanya saat itu
  /// isi lama disembunyikan — membuka/melipat hari tetap menampilkan baris
  /// yang sudah ada supaya tidak berkedip.
  var _isiUsang = false;

  @override
  void didUpdateWidget(DaftarRiwayat lama) {
    super.didUpdateWidget(lama);
    if (lama.saringan != widget.saringan) {
      _hari = widget.repo.watchHariRiwayat(widget.saringan);
      _kunciIsi = null;
      _isiUsang = true;
    }
  }

  bool _terbuka(int i, DateTime tanggal) =>
      _pilihan[tanggal] ?? i < DaftarRiwayat.hariTerbuka;

  /// Aliran isi untuk hari-hari yang terbuka — dibuat ulang hanya kalau
  /// daftar harinya berubah, supaya tidak berkedip.
  Stream<List<Transaction>> _isiUntuk(List<DateTime> terbuka) {
    final kunci = terbuka.map((d) => d.toIso8601String()).join(',');
    if (kunci != _kunciIsi || _isi == null) {
      _kunciIsi = kunci;
      _isi = widget.repo.watchIsiHari(widget.saringan, terbuka);
    }
    return _isi!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RingkasanHari>>(
      stream: _hari,
      builder: (context, snapHari) {
        // Selagi aliran saringan BARU belum menjawab, StreamBuilder masih
        // memegang data saringan LAMA. Dulu transaksi tunai tetap tampil
        // (dan bisa diketuk, bahkan dibatalkan) sesaat sesudah memilih QRIS
        // (review D6, sama dengan Laporan S14). Disembunyikan sampai yang
        // baru datang.
        final hari = snapHari.connectionState == ConnectionState.waiting
            ? null
            : snapHari.data;
        final terbuka = [
          for (final (i, h) in (hari ?? const <RingkasanHari>[]).indexed)
            if (_terbuka(i, h.tanggal)) h.tanggal,
        ];
        // Susunannya SELALU sama, dimuat atau tidak: dulu daftar "memuat"
        // dibangun di luar dua StreamBuilder di bawah, jadi setiap ganti
        // saringan kotak cari di [DaftarRiwayat.kepala] dibuat ulang —
        // tulisannya hilang dan keyboard tertutup.
        return StreamBuilder<List<Transaction>>(
          stream: terbuka.isEmpty ? null : _isiUntuk(terbuka),
          builder: (context, snapIsi) => StreamBuilder<Map<String, String>>(
            stream: _nama,
            builder: (context, snapNama) => _daftar([
              ...widget.kepala,
              if (snapHari.hasError)
                GalatMuat(
                  galat: snapHari.error!,
                  awalan: 'Riwayat gagal dimuat',
                  onCobaLagi: () => setState(() {
                    _hari = widget.repo.watchHariRiwayat(widget.saringan);
                    _kunciIsi = null;
                  }),
                )
              else if (snapIsi.hasError)
                GalatMuat(
                  galat: snapIsi.error!,
                  awalan: 'Riwayat gagal dimuat',
                  onCobaLagi: () => setState(() => _kunciIsi = null),
                )
              else if (hari == null)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (hari.isEmpty)
                widget.kosong(widget.saringan.disaring)
              else
                ..._baris(
                  hari,
                  _isiTerkini(snapIsi),
                  snapNama.data ?? const {},
                ),
            ]),
          ),
        );
      },
    );
  }

  List<Transaction>? _isiTerkini(AsyncSnapshot<List<Transaction>> snap) {
    if (snap.connectionState != ConnectionState.waiting) _isiUsang = false;
    return _isiUsang ? null : snap.data;
  }

  Widget _daftar(List<Widget> isi) => ListView.builder(
        padding: widget.padding,
        itemCount: isi.length,
        itemBuilder: (context, i) => isi[i],
      );

  /// Pita tiap hari, lalu baris transaksinya kalau terbuka. Barisnya
  /// sendiri-sendiri di daftar, jadi hari berisi ratusan transaksi pun hanya
  /// membangun yang terlihat.
  List<Widget> _baris(
    List<RingkasanHari> hari,
    List<Transaction>? isi,
    Map<String, String> nama,
  ) {
    final perHari = <DateTime, List<Transaction>>{};
    for (final t in isi ?? const <Transaction>[]) {
      final l = t.createdAt.toLocal();
      perHari.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(t);
    }
    final repo = widget.repo;
    return [
      for (final (i, h) in hari.indexed) ...[
        PitaHari(
          judul: DateFormat('EEEE, d MMM yyyy', 'id_ID').format(h.tanggal),
          keterangan: '${h.jumlah} Transaksi',
          total: formatRp(h.total),
          terbuka: _terbuka(i, h.tanggal),
          onTap: () => setState(
            () => _pilihan[h.tanggal] = !_terbuka(i, h.tanggal),
          ),
          isi: const [],
        ),
        if (_terbuka(i, h.tanggal)) ...[
          if (isi == null)
            const ColoredBox(
              color: WarnaTeras.kartu,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          for (final t in perHari[h.tanggal] ?? const <Transaction>[])
            ColoredBox(
              color: WarnaTeras.kartu,
              child: BarisTransaksi(
                transaksi: t,
                namaPembatal: t.namaPembatal(nama),
                onTap: () => bukaDetailTransaksi(context, repo, t),
                onBatalkan: repo.bolehDibatalkan(t)
                    ? () => batalkanTransaksiLewatDialog(context, repo, t)
                    : null,
              ),
            ),
        ],
        const SizedBox(height: 14),
      ],
    ];
  }
}
