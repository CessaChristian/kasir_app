import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/teks_teras.dart';
import '../ui/tombol_lembar.dart';
import '../ui/warna_teras.dart';
import '../../utils/pesan_galat.dart';

/// Dialog pembatalan yang dipakai bersama transaksi dan pengeluaran,
/// mengikuti desain: pilih alasan → berhasil.
///
/// Kasir maupun owner cukup mengisi alasan — PIN owner tidak diminta lagi
/// (keputusan owner 2026-10-24): yang owner butuhkan adalah tahu SIAPA yang
/// membatalkan dan KENAPA, dan keduanya tercatat. Kesalahan dari [kirim]
/// ditampilkan di bawah pilihan alasan.
///
/// Mengembalikan true kalau pembatalan berhasil.
Future<bool> tampilkanDialogPembatalan(
  BuildContext context, {
  required String pertanyaan,
  required String judulBerhasil,
  required String keteranganBerhasil,
  required List<String> daftarAlasan,
  required Future<void> Function(String alasan) kirim,
}) async {
  final hasil = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x73281909),
    builder: (_) => DialogPembatalan(
      pertanyaan: pertanyaan,
      judulBerhasil: judulBerhasil,
      keteranganBerhasil: keteranganBerhasil,
      daftarAlasan: daftarAlasan,
      kirim: kirim,
    ),
  );
  return hasil == true;
}

/// Alasan yang mewajibkan isian teks.
const alasanLainnya = 'Lainnya';

enum _Langkah { alasan, berhasil }

class DialogPembatalan extends StatefulWidget {
  final String pertanyaan;
  final String judulBerhasil;
  final String keteranganBerhasil;
  final List<String> daftarAlasan;
  final Future<void> Function(String alasan) kirim;

  const DialogPembatalan({
    super.key,
    required this.pertanyaan,
    required this.judulBerhasil,
    required this.keteranganBerhasil,
    required this.daftarAlasan,
    required this.kirim,
  });

  @override
  State<DialogPembatalan> createState() => _DialogPembatalanState();
}

class _DialogPembatalanState extends State<DialogPembatalan> {
  /// Panjang maksimal alasan "Lainnya".
  static const _panjangAlasanMaks = 100;

  final _lainnyaC = TextEditingController();
  var _langkah = _Langkah.alasan;
  String? _alasan;
  String? _galat;
  var _memproses = false;

  @override
  void dispose() {
    _lainnyaC.dispose();
    super.dispose();
  }

  String get _teksAlasan =>
      _alasan == alasanLainnya ? _lainnyaC.text.trim() : (_alasan ?? '');

  String get _alasanTersimpan =>
      _alasan == alasanLainnya ? '$alasanLainnya: $_teksAlasan' : _teksAlasan;

  Future<void> _kirim() async {
    if (_teksAlasan.isEmpty || _memproses) return;
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      await widget.kirim(_alasanTersimpan);
      if (!mounted) return;
      setState(() {
        _memproses = false;
        _langkah = _Langkah.berhasil;
      });
    } catch (e) {
      // Galat APA PUN mengembalikan tombolnya. Dulu hanya penolakan yang
      // ditangkap; galat lain (mis. database sibuk) membuat dialog macet di
      // "Memproses…" (QA kedua K6).
      _salah(pesanGalat(e, awalan: 'Gagal membatalkan'));
    }
  }

  void _salah(String pesan) {
    if (!mounted) return;
    setState(() {
      _memproses = false;
      _galat = pesan;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Setelah berhasil, menutup dengan tombol kembali tetap melapor true.
      canPop: _langkah != _Langkah.berhasil,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: Dialog(
        backgroundColor: WarnaTeras.kartu,
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          // Bisa digulir: kotak "Lainnya" + keyboard membuat isinya lebih
          // tinggi dari ruang yang tersisa.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: switch (_langkah) {
                _Langkah.alasan => _isiAlasan(),
                _Langkah.berhasil => _isiBerhasil(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _ikon(IconData ikon, Color latar, Color warna, {bool bulat = false}) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(bulat ? 26 : 16),
      ),
      child: Icon(ikon, size: 28, color: warna),
    );
  }

  Widget _judul(String judul, String keterangan) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Text(
          judul,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.menu,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          keterangan,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: TeksTeras.biasa,
            height: 1.45,
            color: WarnaTeras.teksPudar,
          ),
        ),
      ],
    );
  }

  // Ukuran tombol dialog ini (desain: tinggi 44, sudut 12).
  static const _tinggiTombol = 46.0;
  static const _sudutTombol = 12.0;

  Widget _isiAlasan() {
    final siap = _teksAlasan.isNotEmpty && !_memproses;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ikon(Icons.edit_note_rounded, WarnaTeras.merahMuda, WarnaTeras.merah),
        _judul('Alasan pembatalan', widget.pertanyaan),
        const SizedBox(height: 16),
        for (final a in widget.daftarAlasan) ...[
          _pilihan(a),
          const SizedBox(height: 8),
        ],
        if (_alasan == alasanLainnya)
          TextField(
            controller: _lainnyaC,
            autofocus: true,
            maxLines: 2,
            maxLength: _panjangAlasanMaks,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: TeksTeras.biasa),
            decoration: InputDecoration(
              hintText: 'Tulis alasan…',
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE6DED6)),
              ),
            ),
          ),
        if (_galat != null) ...[
          const SizedBox(height: 8),
          Text(
            _galat!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.merah,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 10,
              child: TombolLembar(
                label: 'Batal',
                latar: WarnaTeras.latarAbu,
                warna: WarnaTeras.teks,
                tinggi: _tinggiTombol,
                sudut: _sudutTombol,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 14,
              child: TombolLembar(
                label: _memproses ? 'Memproses…' : 'Batalkan',
                latar: WarnaTeras.merah,
                warna: Colors.white,
                tinggi: _tinggiTombol,
                sudut: _sudutTombol,
                onPressed: siap ? _kirim : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pilihan(String alasan) {
    final aktif = _alasan == alasan;
    return Material(
      color: aktif ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: aktif ? WarnaTeras.oranye : const Color(0xFFE6DED6),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _alasan = alasan;
          _galat = null;
        }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                aktif
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: aktif ? WarnaTeras.oranye : WarnaTeras.titikPasif,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alasan,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: aktif
                        ? const Color(0xFFC46A12)
                        : WarnaTeras.teksSedang,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _isiBerhasil() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ikon(
          Icons.check_circle_rounded,
          WarnaTeras.hijauMuda,
          WarnaTeras.hijau,
          bulat: true,
        ),
        _judul(widget.judulBerhasil, widget.keteranganBerhasil),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: TombolLembar(
            label: 'Selesai',
            latar: WarnaTeras.oranye,
            warna: Colors.white,
            tinggi: _tinggiTombol,
            sudut: _sudutTombol,
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
      ],
    );
  }
}

/// Keterangan pembatalan: kapan, oleh siapa, dan alasannya — untuk
/// transaksi maupun pengeluaran.
class InfoPembatalan extends StatelessWidget {
  final DateTime dibatalkanPada;
  final String? alasan;
  final String? namaPembatal;
  final bool ringkas;

  const InfoPembatalan({
    super.key,
    required this.dibatalkanPada,
    this.alasan,
    this.namaPembatal,
    this.ringkas = false,
  });

  @override
  Widget build(BuildContext context) {
    final kapan = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(dibatalkanPada.toLocal());
    // Yang terhapus SEBELUM fitur pembatalan tidak punya catatan.
    final teksAlasan =
        alasan ?? 'Alasan tidak tercatat (dihapus sebelum fitur pembatalan)';
    final oleh = namaPembatal != null ? ' · oleh $namaPembatal' : '';

    final teks = Text(
      ringkas ? '$teksAlasan$oleh' : 'Dibatalkan $kapan$oleh\n$teksAlasan',
      style: TextStyle(fontSize: ringkas ? 12 : 13, color: Colors.red.shade700),
      maxLines: ringkas ? 2 : null,
      overflow: ringkas ? TextOverflow.ellipsis : null,
    );
    if (ringkas) return teks;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: teks),
        ],
      ),
    );
  }
}

/// Label merah kecil "DIBATALKAN".
class LabelDibatalkan extends StatelessWidget {
  const LabelDibatalkan({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'DIBATALKAN',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.red.shade700,
        ),
      ),
    );
  }
}
