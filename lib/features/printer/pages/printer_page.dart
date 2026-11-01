import 'package:flutter/material.dart';

import '../../../shared/ui/bingkai_halaman.dart';
import '../../../shared/ui/dialog_memuat.dart';
import '../../../shared/ui/kartu_teras.dart';
import '../../../shared/ui/segarkan/pengendali_segarkan.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../data/layanan_printer.dart';
import '../data/logo_cetak.dart';
import '../data/struk_cetak.dart';

enum _Keadaan { memuat, bluetoothMati, tanpaIzin, siap }

/// Status printer yang dipakai — hasil mencoba menyambung, bukan sekadar
/// "pernah dipasangkan" (printer yang mati tetap ada di daftar Android).
enum _Status { memeriksa, tersambung, tidakTerhubung }

/// Profil → Printer Struk: pilih printer Bluetooth dan Test Print. Berlaku
/// untuk HP ini saja. Kertas selalu 58 mm dan tidak ada cetak otomatis —
/// struk dicetak hanya lewat tombol Cetak Struk (keputusan owner
/// 2026-11-01).
///
/// Hanya PRINTER yang ditampilkan, bukan semua perangkat Bluetooth yang
/// pernah dipasangkan (headset, speaker, mobil). Printer dipasangkan lewat
/// Pengaturan Bluetooth HP — sama dengan Moka; tombolnya ada di sini.
class PrinterPage extends StatefulWidget {
  final LayananPrinter? layanan;

  const PrinterPage({super.key, this.layanan});

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> with WidgetsBindingObserver {
  late final _l = widget.layanan ?? LayananPrinter.instance;
  var _keadaan = _Keadaan.memuat;
  var _atur = const PengaturanPrinter();
  var _daftar = const <PrinterTerpasang>[];
  var _status = _Status.memeriksa;

  /// Hasil pemeriksaan yang sudah usang (printer diganti / dimuat ulang di
  /// tengah jalan) diabaikan.
  var _urutPeriksa = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muat();
  }

  /// Tombol segarkan di header: selain sinkron server, daftar printer juga
  /// dimuat ulang — printer yang baru dipasangkan langsung terlihat.
  PengendaliSegarkan? _segarkan;
  var _segarkanBerjalan = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final baru = BingkaiHalaman.pengendaliDari(context);
    if (baru == _segarkan) return;
    _segarkan?.removeListener(_dengarSegarkan);
    _segarkan = baru?..addListener(_dengarSegarkan);
  }

  void _dengarSegarkan() {
    final berjalan = _segarkan?.berjalan ?? false;
    if (berjalan && !_segarkanBerjalan) _muat();
    _segarkanBerjalan = berjalan;
  }

  @override
  void dispose() {
    _segarkan?.removeListener(_dengarSegarkan);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Kembali dari Pengaturan Bluetooth: printer yang baru dipasangkan
  /// langsung muncul tanpa mengetuk Muat ulang.
  ///
  /// Hanya sesudah aplikasi benar-benar tertutup layar lain. Popup izin
  /// Bluetooth juga membuat aplikasi "kembali aktif"; memuat ulang di situ
  /// meminta izin lagi — popup yang ditolak muncul berulang.
  var _tertutup = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _tertutup = true;
    } else if (state == AppLifecycleState.resumed && _tertutup) {
      _tertutup = false;
      _muat();
    }
  }

  Future<void> _muat() async {
    setState(() => _keadaan = _Keadaan.memuat);
    var atur = await _l.muat();
    // Izin dulu — lihat LayananPrinter.bluetoothNyala.
    final keadaan = !await _l.izinAda()
        ? _Keadaan.tanpaIzin
        : !await _l.bluetoothNyala()
        ? _Keadaan.bluetoothMati
        : _Keadaan.siap;
    final daftar = keadaan == _Keadaan.siap
        ? await _l.terpasang()
        : const <PrinterTerpasang>[];
    // Satu-satunya printer langsung dipakai kalau belum ada pilihan yang
    // masih terpasang — toko biasanya hanya punya satu printer per HP.
    if (daftar.length == 1 && !daftar.any((p) => p.mac == atur.mac)) {
      atur = PengaturanPrinter(
        mac: daftar.single.mac,
        nama: daftar.single.nama,
      );
      await _l.simpan(atur);
    }
    if (!mounted) return;
    setState(() {
      _atur = atur;
      _keadaan = keadaan;
      _daftar = daftar;
    });
    await _periksa();
  }

  Future<void> _pilih(PrinterTerpasang p) async {
    final baru = PengaturanPrinter(mac: p.mac, nama: p.nama);
    setState(() => _atur = baru);
    await _l.simpan(baru);
    await _periksa();
  }

  /// Coba sambungkan printer yang dipakai untuk tahu apakah ia menyala.
  /// Tidak diulang sendiri di belakang layar — hemat baterai; diperiksa
  /// lagi saat dimuat ulang, segarkan, ganti printer, atau Coba lagi.
  Future<void> _periksa() async {
    if (!_bisaTest) return;
    final urut = ++_urutPeriksa;
    setState(() => _status = _Status.memeriksa);
    final ok = await _l.periksa();
    if (!mounted || urut != _urutPeriksa) return;
    setState(() => _status = ok ? _Status.tersambung : _Status.tidakTerhubung);
  }

  Future<void> _testPrint() async {
    final hasil = await jalankanDenganMemuat(
      context,
      () async => _l.cetak(
        keEscPos(
          susunTestPrint(namaPrinter: _atur.nama ?? '-', waktu: DateTime.now()),
          logo: await logoEscPos(),
        ),
      ),
      pesan: 'Mencetak percobaan…',
    );
    if (!mounted) return;
    final pesan = pesanCetak(hasil);
    // Hasil cetak juga kabar status printer yang paling baru.
    setState(
      () => _status = hasil == HasilCetak.berhasil
          ? _Status.tersambung
          : _Status.tidakTerhubung,
    );
    pesan == null
        ? AppToast.success(context, 'Test print terkirim ke ${_atur.nama}')
        : AppToast.error(context, pesan);
  }

  bool get _bisaTest =>
      _keadaan == _Keadaan.siap && _daftar.any((p) => p.mac == _atur.mac);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const _Judul('PRINTER'),
        _isi(),
        if (_keadaan == _Keadaan.siap && _daftar.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Printer lain belum muncul? Pasangkan dulu di Pengaturan '
                  'Bluetooth HP.',
                  style: TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksSamar,
                  ),
                ),
              ),
              TextButton(
                onPressed: _l.bukaPengaturanBluetooth,
                style: TextButton.styleFrom(foregroundColor: WarnaTeras.oranye),
                child: const Text('Buka Bluetooth'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        TombolLembar(
          label: 'Test Print',
          ikon: Icons.print_rounded,
          latar: WarnaTeras.oranye,
          warna: Colors.white,
          tinggi: 46,
          sudut: 8,
          onPressed: _bisaTest ? _testPrint : null,
        ),
      ],
    );
  }

  Widget _isi() {
    switch (_keadaan) {
      case _Keadaan.memuat:
        return const KartuTeras(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _Keadaan.tanpaIzin:
        return _Kosong(
          ikon: Icons.lock_outline_rounded,
          judul: 'Izin Bluetooth dibutuhkan',
          teks:
              'Izinkan aplikasi memakai "Perangkat di sekitar" supaya bisa '
              'mencetak ke printer Bluetooth.',
          tombol: 'Beri izin',
          onTap: _muat,
          // Ditolak dua kali: Android tidak memunculkan popup izin lagi,
          // tombol Beri izin tidak berbuat apa-apa — izinnya hanya bisa
          // dinyalakan dari halaman izin aplikasi.
          tautan: 'Popup izin tidak muncul? Buka Pengaturan Izin',
          onTautan: _l.bukaPengaturanIzin,
        );
      case _Keadaan.bluetoothMati:
        return _Kosong(
          ikon: Icons.bluetooth_disabled_rounded,
          judul: 'Bluetooth mati',
          teks: 'Nyalakan Bluetooth HP untuk memakai printer struk.',
          tombol: 'Buka Pengaturan Bluetooth',
          onTap: _l.bukaPengaturanBluetooth,
        );
      case _Keadaan.siap:
        break;
    }
    if (_daftar.isEmpty) {
      return _Kosong(
        ikon: Icons.print_disabled_rounded,
        judul: 'Belum ada printer',
        teks:
            '1. Nyalakan printer struk.\n'
            '2. Buka Pengaturan Bluetooth, lalu pasangkan printernya.\n'
            '3. Kembali ke sini — printer langsung muncul.',
        tombol: 'Buka Pengaturan Bluetooth',
        onTap: _l.bukaPengaturanBluetooth,
      );
    }
    return KartuTeras(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < _daftar.length; i++) ...[
            if (i > 0) const GarisTeras(jarak: 0),
            _barisPrinter(_daftar[i]),
          ],
        ],
      ),
    );
  }

  Widget _barisPrinter(PrinterTerpasang p) {
    final dipakai = p.mac == _atur.mac;
    return InkWell(
      onTap: dipakai ? null : () => _pilih(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: dipakai ? WarnaTeras.oranyeLembut : WarnaTeras.latar,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.print_rounded,
                color: dipakai ? WarnaTeras.oranye : WarnaTeras.teksSamar,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nama.isEmpty ? 'Printer tanpa nama' : p.nama,
                    style: const TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teks,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (dipakai)
                    _keteranganStatus()
                  else
                    const Text(
                      'Ketuk untuk memakai',
                      style: TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksSamar,
                      ),
                    ),
                ],
              ),
            ),
            if (dipakai)
              const Icon(Icons.check_circle_rounded, color: WarnaTeras.oranye),
          ],
        ),
      ),
    );
  }

  Widget _keteranganStatus() {
    switch (_status) {
      case _Status.memeriksa:
        return const Row(
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Memeriksa printer…',
                style: TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.teksSamar,
                ),
              ),
            ),
          ],
        );
      case _Status.tersambung:
        return const Row(
          children: [
            Icon(Icons.circle, size: 9, color: WarnaTeras.hijau),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Tersambung · siap mencetak',
                style: TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.hijau,
                ),
              ),
            ),
          ],
        );
      case _Status.tidakTerhubung:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.circle_outlined,
                    size: 9,
                    color: WarnaTeras.merah,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tidak terhubung — nyalakan printer dan dekatkan ke HP.',
                    style: TextStyle(
                      fontSize: TeksTeras.kecil,
                      color: WarnaTeras.merah,
                    ),
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: _periksa,
              child: const Padding(
                padding: EdgeInsets.only(top: 6, left: 15),
                child: Text(
                  'Coba lagi',
                  style: TextStyle(
                    fontSize: TeksTeras.kecil,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.oranye,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _Judul extends StatelessWidget {
  final String teks;

  const _Judul(this.teks);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      teks,
      style: const TextStyle(
        fontSize: TeksTeras.kecil,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: WarnaTeras.teksSamar,
      ),
    ),
  );
}

/// Kartu keadaan kosong/terhalang: ikon, judul, penjelasan, satu tombol.
class _Kosong extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String teks;
  final String tombol;
  final VoidCallback onTap;
  final String? tautan;
  final VoidCallback? onTautan;

  const _Kosong({
    required this.ikon,
    required this.judul,
    required this.teks,
    required this.tombol,
    required this.onTap,
    this.tautan,
    this.onTautan,
  });

  @override
  Widget build(BuildContext context) => KartuTeras(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: WarnaTeras.oranyeLembut,
            shape: BoxShape.circle,
          ),
          child: Icon(ikon, size: 28, color: WarnaTeras.oranye),
        ),
        const SizedBox(height: 12),
        Text(
          judul,
          style: const TextStyle(
            fontSize: TeksTeras.judulBagian,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          teks,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.kecil,
            height: 1.5,
            color: WarnaTeras.teksSamar,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: TombolLembar(
            label: tombol,
            latar: WarnaTeras.oranye,
            warna: Colors.white,
            tinggi: 42,
            sudut: 8,
            onPressed: onTap,
          ),
        ),
        if (tautan != null)
          TextButton(
            onPressed: onTautan,
            style: TextButton.styleFrom(foregroundColor: WarnaTeras.oranye),
            child: Text(
              tautan!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: TeksTeras.kecil),
            ),
          ),
      ],
    ),
  );
}
