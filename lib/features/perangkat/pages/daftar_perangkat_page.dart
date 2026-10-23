import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../data/supabase/server_terjangkau.dart';
import '../../../data/sync/sync_service.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/ui/chip_status.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/kolom_lembar.dart';
import '../../../shared/ui/layar_butuh_internet.dart';
import '../../../shared/ui/lembar_bawah.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/pesan_galat.dart';
import '../../owner/repositories/cashier_repository.dart'
    show pesanButuhInternet;

/// Panjang maksimal nama perangkat.
const panjangNamaPerangkat = 30;

/// "Terakhir aktif" di kartu: perangkat ini "Sedang aktif"; yang lain
/// selalu jam terakhirnya sinkron — HP yang sinkron semenit lalu bisa saja
/// sudah mati (keputusan owner 2026-10-13).
String labelTerakhirAktif(
  Perangkat p, {
  required bool iniSaya,
  required DateTime sekarang,
}) {
  if (iniSaya) return 'Sedang aktif';
  return _labelWaktu(p.terakhirAktif, sekarang);
}

/// "Data terakhir diterima" di kartu: kapan HP itu terakhir selesai menarik
/// data dengan bersih (`terakhir_tarik`).
String labelTerakhirTarik(Perangkat p, {required DateTime sekarang}) {
  final t = p.terakhirTarik;
  return t == null ? 'Belum ada' : _labelWaktu(t, sekarang);
}

String _labelWaktu(DateTime t, DateTime sekarang) {
  final hariIni =
      t.year == sekarang.year &&
      t.month == sekarang.month &&
      t.day == sekarang.day;
  final jam = DateFormat('HH:mm').format(t);
  if (hariIni) return 'Hari ini, $jam';
  return '${DateFormat('d MMM yyyy', 'id_ID').format(t)}, $jam';
}

/// Urutan desain: perangkat ini paling atas, lalu yang aktif (terakhir
/// dipakai di atas), lalu kelompok DICABUT.
(List<Perangkat>, List<Perangkat>) kelompokkanPerangkat(
  List<Perangkat> semua,
  String? idSaya,
) {
  int urut(Perangkat a, Perangkat b) {
    if (a.id == idSaya) return -1;
    if (b.id == idSaya) return 1;
    return b.terakhirAktif.compareTo(a.terakhirAktif);
  }

  return (
    [
      for (final p in semua)
        if (p.aktif) p,
    ]..sort(urut),
    [
      for (final p in semua)
        if (!p.aktif) p,
    ]..sort(urut),
  );
}

/// Daftar Perangkat (desain) — hak PATEN pemilik.
///
/// ── KENAPA HALAMAN INI ADA ──
///
/// Mencabut sebuah HP dulu berarti mengganti password akun perangkat, dan itu
/// melempar SEMUA HP sekaligus. Di sini pencabutan mengenai satu HP saja, dan
/// berlaku pada permintaan berikutnya — tidak menunggu tiketnya habis.
///
/// ── KENAPA BUTUH INTERNET ──
///
/// Daftar ini sengaja tidak ikut sinkronisasi. Kalau ikut, keputusan mencabut
/// bisa diambil dari salinan yang basi — dan HP yang baru saja dipulihkan
/// pemilik bisa tercabut lagi oleh salinan lama. Jadi dibaca langsung dari
/// server, apa adanya. Tombol segarkan di header menjalankan sinkron (yang
/// juga memperbarui "terakhir aktif" HP ini), lalu daftarnya dibaca ulang.
class DaftarPerangkatPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai [PerangkatRepository.instance].
  final PerangkatRepository? repo;

  /// Pemeriksa koneksi. Bawaan: [serverTerjangkau].
  final Future<bool> Function()? cekKoneksi;

  const DaftarPerangkatPage({super.key, this.repo, this.cekKoneksi});

  @override
  State<DaftarPerangkatPage> createState() => _DaftarPerangkatPageState();
}

enum _Keadaan { memuat, offline, belumDisiapkan, siap }

class _DaftarPerangkatPageState extends State<DaftarPerangkatPage> {
  late final _repo = widget.repo ?? PerangkatRepository.instance;
  late final _cekKoneksi = widget.cekKoneksi ?? serverTerjangkau;

  var _keadaan = _Keadaan.memuat;
  var _memeriksa = false;
  List<Perangkat> _daftar = const [];

  @override
  void initState() {
    super.initState();
    // Hak paten owner. Menu sudah disembunyikan untuk kasir, tapi halaman ini
    // tetap bisa dibuka lewat jalur lain — jadi diperiksa juga di sini.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        SessionManager.instance.requireOwner();
      } on StateError {
        if (mounted) Navigator.of(context).pop();
      }
    });
    SyncService.instance.terakhirBerhasil.addListener(_sesudahSync);
    _muat();
  }

  @override
  void dispose() {
    SyncService.instance.terakhirBerhasil.removeListener(_sesudahSync);
    super.dispose();
  }

  void _sesudahSync() {
    if (_keadaan == _Keadaan.siap) _muat(diam: true);
  }

  /// [diam] = tanpa memperlihatkan pemuat (memuat ulang sesudah aksi/sinkron).
  Future<void> _muat({bool diam = false}) async {
    setState(() {
      _memeriksa = true;
      if (!diam) _keadaan = _Keadaan.memuat;
    });
    _Keadaan keadaan;
    var daftar = _daftar;
    if (!await _cekKoneksi()) {
      keadaan = _Keadaan.offline;
    } else {
      try {
        daftar = await _repo.semua();
        keadaan = _Keadaan.siap;
      } catch (e) {
        keadaan = PerangkatRepository.belumDisiapkan(e)
            ? _Keadaan.belumDisiapkan
            : _Keadaan.offline;
      }
    }
    if (!mounted) return;
    setState(() {
      _keadaan = keadaan;
      _daftar = daftar;
      _memeriksa = false;
    });
  }

  Future<void> _jalankan(Future<void> Function() aksi, String pesan) async {
    try {
      await aksi();
      if (mounted) AppToast.success(context, pesan);
      await _muat(diam: true);
    } catch (e) {
      if (!mounted) return;
      if (!await _cekKoneksi()) {
        if (!mounted) return;
        setState(() => _keadaan = _Keadaan.offline);
        AppToast.error(context, pesanButuhInternet);
        return;
      }
      if (!mounted) return;
      // Fungsi servernya ditambahkan lewat berkas SQL yang dijalankan pemilik.
      // Pesan mentah PostgREST tidak berarti apa-apa bagi pemilik warung —
      // yang dia butuhkan adalah tahu APA yang harus dilakukan.
      AppToast.error(
        context,
        PerangkatRepository.belumDisiapkan(e)
            ? 'Perlu menjalankan ulang supabase/perangkat.sql di Supabase'
            : pesanGalat(e),
      );
    }
  }

  Future<void> _gantiNama(Perangkat p) async {
    final hasil = await tampilkanLembarBawah<Object?>(
      context,
      (_) => _LembarGantiNama(perangkat: p),
    );
    if (hasil is! String) return;
    await _jalankan(
      () => _repo.ubahNama(p.id, hasil),
      'Nama perangkat diperbarui',
    );
  }

  Future<void> _cabut(Perangkat p) async {
    final ya = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.block_rounded,
      judul: 'Cabut perangkat?',
      catatan:
          '${p.nama} akan langsung keluar dan tidak bisa mengakses aplikasi '
          'sampai dipulihkan.',
      labelAksi: 'Cabut',
    );
    if (!ya) return;
    await _jalankan(
      () => _repo.ubahStatus(p.id, aktif: false),
      '${p.nama} dicabut',
    );
  }

  /// Tanpa konfirmasi (desain): memulihkan tidak merugikan siapa pun.
  Future<void> _pulihkan(Perangkat p) => _jalankan(
    () => _repo.ubahStatus(p.id, aktif: true),
    '${p.nama} dipulihkan',
  );

  Future<void> _lupakan(Perangkat p) async {
    final ya = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.delete_rounded,
      judul: 'Lupakan perangkat?',
      catatan:
          '${p.nama} akan dihapus permanen dari daftar. Perangkat harus '
          'didaftarkan ulang untuk bisa dipakai.',
      labelAksi: 'Lupakan',
    );
    if (!ya) return;
    await _jalankan(() => _repo.lupakan(p.id), '${p.nama} dilupakan');
  }

  @override
  Widget build(BuildContext context) {
    return HalamanTurunan(
      judul: 'Daftar Perangkat',
      child: switch (_keadaan) {
        _Keadaan.memuat => const Center(child: CircularProgressIndicator()),
        _Keadaan.offline => LayarButuhInternet(
          keterangan:
              'Daftar Perangkat hanya bisa dibuka saat online agar daftar '
              'perangkat dan status aksesnya selalu terbaru.',
          memeriksa: _memeriksa,
          onCobaLagi: _muat,
        ),
        _Keadaan.belumDisiapkan => const _PesanTengah(
          'Daftar perangkat belum disiapkan di server. Jalankan '
          'supabase/perangkat.sql lebih dulu.',
        ),
        _Keadaan.siap => _isi(),
      },
    );
  }

  Widget _isi() {
    if (_daftar.isEmpty) {
      return const _PesanTengah('Belum ada perangkat terdaftar');
    }
    final idSaya = _repo.idSaya;
    final (aktif, dicabut) = kelompokkanPerangkat(_daftar, idSaya);
    final sekarang = DateTime.now();
    Widget kartu(Perangkat p) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _KartuPerangkat(
        perangkat: p,
        iniSaya: p.id == idSaya,
        sekarang: sekarang,
        perluDicek: p.perluDicek(sekarang: sekarang, idSaya: idSaya),
        masalahData: p.masalahData(sekarang: sekarang, idSaya: idSaya),
        onGantiNama: () => _gantiNama(p),
        onCabut: () => _cabut(p),
        onPulihkan: () => _pulihkan(p),
        onLupakan: () => _lupakan(p),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final p in aktif) kartu(p),
        if (dicabut.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              'DICABUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: WarnaTeras.teksSamar,
              ),
            ),
          ),
          for (final p in dicabut) kartu(p),
        ],
      ],
    );
  }
}

class _PesanTengah extends StatelessWidget {
  final String teks;

  const _PesanTengah(this.teks);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          teks,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: WarnaTeras.teksPudar),
        ),
      ),
    );
  }
}

IconData _ikonPerangkat(Perangkat p) =>
    p.tablet ? Icons.tablet_android_rounded : Icons.smartphone_rounded;

class _KartuPerangkat extends StatelessWidget {
  final Perangkat perangkat;
  final bool iniSaya;
  final bool perluDicek;
  final ({String judul, String catatan})? masalahData;
  final DateTime sekarang;
  final VoidCallback onGantiNama;
  final VoidCallback onCabut;
  final VoidCallback onPulihkan;
  final VoidCallback onLupakan;

  const _KartuPerangkat({
    required this.perangkat,
    required this.iniSaya,
    required this.perluDicek,
    required this.masalahData,
    required this.sekarang,
    required this.onGantiNama,
    required this.onCabut,
    required this.onPulihkan,
    required this.onLupakan,
  });

  static const _biruMuda = Color(0xFFE8F0FB);
  static const _abuMuda = Color(0xFFF1ECE7);

  @override
  Widget build(BuildContext context) {
    final p = perangkat;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iniSaya ? WarnaTeras.garisOranye : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: p.aktif ? _biruMuda : _abuMuda,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _ikonPerangkat(p),
                  size: 24,
                  color: p.aktif ? WarnaTeras.biru : WarnaTeras.teksSamar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _namaDanModel()),
              const SizedBox(width: 8),
              p.aktif
                  ? const ChipStatus(label: 'Aktif', aktif: true)
                  : const ChipStatus(
                      label: 'Dicabut',
                      aktif: false,
                      warna: WarnaTeras.merah,
                      latar: WarnaTeras.merahMuda,
                    ),
            ],
          ),
          if (perluDicek)
            _peringatan(
              'Tidak sinkron ${p.hariDiam(sekarang: sekarang)} hari',
              'Lakukan sinkron atau cabut dan lupakan device!',
            )
          else if (masalahData case final m?)
            _peringatan(m.judul, m.catatan),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: WarnaTeras.garis),
          const SizedBox(height: 12),
          _barisInfo(
            'Terakhir aktif',
            labelTerakhirAktif(p, iniSaya: iniSaya, sekarang: sekarang),
          ),
          if (p.aktif) ...[
            const SizedBox(height: 4),
            _barisInfo(
              'Data terakhir diterima',
              labelTerakhirTarik(p, sekarang: sekarang),
            ),
          ],
          const SizedBox(height: 4),
          _barisInfo(
            'Didaftarkan',
            DateFormat('d MMM yyyy', 'id_ID').format(p.didaftarkan),
          ),
          const SizedBox(height: 12),
          _tombol(),
        ],
      ),
    );
  }

  Widget _namaDanModel() {
    final p = perangkat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
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
            if (iniSaya) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranyeMuda,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'Perangkat ini',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (p.model != null) ...[
          const SizedBox(height: 2),
          Text(
            p.model!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: WarnaTeras.teksPudar),
          ),
        ],
      ],
    );
  }

  Widget _peringatan(String judul, String catatan) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF6DDB0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sync_problem_rounded,
            size: 18,
            color: Color(0xFFC77A0A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A5300),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  catatan,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: Color(0xFF7A6550),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barisInfo(String label, String nilai) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            nilai,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teks,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tombol() {
    Widget tombol(
      String label,
      IconData ikon,
      VoidCallback onTap, {
      Color latar = WarnaTeras.kartu,
      Color warna = const Color(0xFF5A5048),
      Color? tepi,
    }) => Expanded(
      child: TombolLembar(
        label: label,
        ikon: ikon,
        latar: latar,
        warna: warna,
        tepi: tepi,
        tinggi: 36,
        sudut: 10,
        ukuranTeks: 12,
        onPressed: onTap,
      ),
    );

    final gantiNama = tombol(
      'Ganti Nama',
      Icons.edit_rounded,
      onGantiNama,
      tepi: const Color(0xFFE6DED6),
    );
    return Row(
      spacing: 8,
      children: [
        gantiNama,
        // Perangkat ini sendiri sengaja tidak bisa dicabut dari sini: server
        // pun menolaknya. Kalau boleh, pemilik bisa mengunci dirinya keluar
        // hanya dengan satu kali salah pencet.
        if (!iniSaya && perangkat.aktif)
          tombol(
            'Cabut',
            Icons.block_rounded,
            onCabut,
            latar: WarnaTeras.merahMuda,
            warna: WarnaTeras.merah,
          ),
        if (!iniSaya && !perangkat.aktif) ...[
          tombol(
            'Pulihkan',
            Icons.settings_backup_restore_rounded,
            onPulihkan,
            latar: WarnaTeras.oranyeMuda,
            warna: WarnaTeras.oranye,
          ),
          tombol(
            'Lupakan',
            Icons.delete_rounded,
            onLupakan,
            warna: WarnaTeras.merah,
            tepi: const Color(0xFFF0B7B1),
          ),
        ],
      ],
    );
  }
}

/// Lembar "Ganti Nama Perangkat" (desain). Hasil: nama baru, atau bukan
/// String kalau batal/tidak berubah.
class _LembarGantiNama extends StatefulWidget {
  final Perangkat perangkat;

  const _LembarGantiNama({required this.perangkat});

  @override
  State<_LembarGantiNama> createState() => _LembarGantiNamaState();
}

class _LembarGantiNamaState extends State<_LembarGantiNama> {
  late final _nama = TextEditingController(text: widget.perangkat.nama);
  String _galat = '';

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  void _simpan() {
    final nama = _nama.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nama.isEmpty) {
      setState(() => _galat = 'Nama perangkat wajib diisi');
      return;
    }
    Navigator.pop(context, nama == widget.perangkat.nama ? null : nama);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.perangkat.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: WarnaTeras.oranye,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.edit_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ganti Nama Perangkat',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                  if (model != null)
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: WarnaTeras.teksSamar,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        KolomLembar(
          controller: _nama,
          ikon: _ikonPerangkat(widget.perangkat),
          petunjuk: 'Nama perangkat',
          galat: _galat.isNotEmpty,
          autofocus: true,
          inputFormatters: [
            LengthLimitingTextInputFormatter(panjangNamaPerangkat),
          ],
          onChanged: (_) {
            if (_galat.isNotEmpty) setState(() => _galat = '');
          },
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 16),
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            _galat,
            style: const TextStyle(fontSize: 12, color: WarnaTeras.merah),
          ),
        ),
        TombolBatalSimpan(labelSimpan: 'Simpan', onSimpan: _simpan),
      ],
    );
  }
}
