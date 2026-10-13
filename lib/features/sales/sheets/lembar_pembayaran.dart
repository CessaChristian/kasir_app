import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/pegang_lembar.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../utils/currency_formatter.dart';
import '../models/pesanan.dart';

/// Batas digit uang diterima: sampai Rp9.999.999.999.
const digitMaksUangDiterima = 10;

/// Lembar pembayaran (desain). Tunai: uang diterima + status kurang/pas/
/// kembalian + nominal cepat ("Rp 16.000" = uang pas). QRIS: nominal + pengingat, lalu "Sudah Bayar".
///
/// [bayar] menyimpan transaksinya dengan uang yang diterima; lembar tetap
/// terbuka (dan tidak bisa ditutup) selama itu berjalan, lalu tertutup
/// kalau berhasil. Hasil: true = sudah dibayar.
Future<bool> tampilkanPembayaran(
  BuildContext context, {
  required int total,
  required MetodeBayar metode,
  required Future<void> Function(int dibayar) bayar,
}) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) =>
        _LembarPembayaran(total: total, metode: metode, bayar: bayar),
  );
  return hasil == true;
}

class _LembarPembayaran extends StatefulWidget {
  final int total;
  final MetodeBayar metode;
  final Future<void> Function(int dibayar) bayar;

  const _LembarPembayaran({
    required this.total,
    required this.metode,
    required this.bayar,
  });

  @override
  State<_LembarPembayaran> createState() => _LembarPembayaranState();
}

class _LembarPembayaranState extends State<_LembarPembayaran> {
  final _uang = TextEditingController();
  var _memproses = false;

  bool get _tunai => widget.metode == MetodeBayar.tunai;
  int? get _diterima => parseRupiah(_uang.text);

  @override
  void dispose() {
    _uang.dispose();
    super.dispose();
  }

  bool get _bisaBayar {
    if (!_tunai) return true;
    final s = statusUang(widget.total, _diterima);
    return s == StatusUang.pas || s == StatusUang.kembalian;
  }

  Future<void> _konfirmasi() async {
    if (_memproses || !_bisaBayar) return;
    setState(() => _memproses = true);
    try {
      await widget.bayar(_tunai ? _diterima! : widget.total);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _memproses = false);
      final pesan = e is StateError
          ? e.message
          : e is ArgumentError
          ? '${e.message}'
          : '$e';
      AppToast.error(context, 'Gagal: $pesan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Jangan sampai lembar tertutup di tengah penyimpanan: galatnya tidak
      // akan terlihat, dan kasir mengira transaksinya aman.
      canPop: !_memproses,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PegangLembar(),
                const SizedBox(height: 18),
                _kepala(),
                if (_tunai) ..._isiTunai() else ..._isiQris(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kepala() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: WarnaTeras.oranye,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.metode.ikon, size: 22, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pembayaran ${widget.metode.label}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WarnaTeras.teks,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _tunai
                    ? 'Masukkan jumlah uang diterima'
                    : 'Pelanggan membayar lewat QRIS',
                style: const TextStyle(
                  fontSize: 12,
                  color: WarnaTeras.teksSamar,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _isiTunai() {
    final status = statusUang(widget.total, _diterima);
    final nominal = nominalCepat(widget.total);
    return [
      const SizedBox(height: 14),
      _barisTotal(),
      const SizedBox(height: 8),
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD6D0CA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 20,
              color: WarnaTeras.oranye,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _uang,
                autofocus: true,
                enabled: !_memproses,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(digitMaksUangDiterima),
                  RupiahInputFormatter(),
                ],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _konfirmasi(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WarnaTeras.teks,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Uang diterima',
                  hintStyle: TextStyle(
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFB5ADA6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: status == StatusUang.kosong
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _barisStatus(status),
              ),
      ),
      const SizedBox(height: 14),
      // Desain: lebar sama, tiga per baris.
      LayoutBuilder(
        builder: (context, ukuran) {
          final lebar = (ukuran.maxWidth - 2 * 12) / 3;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final n in nominal)
                SizedBox(width: lebar, child: _nominal(n)),
            ],
          );
        },
      ),
      const SizedBox(height: 22),
      TombolLembar(
        label: _memproses ? 'Memproses…' : 'Konfirmasi pembayaran',
        latar: WarnaTeras.oranye,
        warna: Colors.white,
        latarNonaktif: const Color(0xFFA3A3A3),
        beratTeks: FontWeight.w500,
        tinggi: 46,
        sudut: 6,
        ukuranTeks: 15,
        onPressed: _bisaBayar && !_memproses ? _konfirmasi : null,
      ),
    ];
  }

  Widget _barisTotal() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WarnaTeras.latar,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Total belanja',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: WarnaTeras.teks,
              ),
            ),
          ),
          Text(
            formatRp(widget.total),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.oranye,
            ),
          ),
        ],
      ),
    );
  }

  Widget _barisStatus(StatusUang s) {
    final kurang = s == StatusUang.kurang;
    final warna = kurang ? WarnaTeras.merah : WarnaTeras.hijau;
    final selisih = (_diterima ?? 0) - widget.total;
    final (ikon, label, nilai) = switch (s) {
      StatusUang.kurang => (
        Icons.error_rounded,
        'Uang kurang',
        formatRp(-selisih),
      ),
      StatusUang.pas => (Icons.check_circle_rounded, 'Uang pas', ''),
      _ => (Icons.check_circle_rounded, 'Kembalian', formatRp(selisih)),
    };
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kurang ? WarnaTeras.merahMuda : WarnaTeras.hijauMuda,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: warna.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(ikon, size: 20, color: warna),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: warna)),
          ),
          Text(
            nilai,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nominal(int n) {
    final dipilih = _diterima == n;
    return Material(
      color: dipilih ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFFF0A94E)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: _memproses
            ? null
            : () => setState(() => _uang.text = formatRupiah(n)),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatRp(n),
              style: const TextStyle(fontSize: 14, color: WarnaTeras.teks),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _isiQris() => [
    const SizedBox(height: 14),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: WarnaTeras.latar,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text(
            'Nominal pembayaran',
            style: TextStyle(fontSize: 13, color: WarnaTeras.teksPudar),
          ),
          const SizedBox(height: 6),
          Text(
            formatRp(widget.total),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.oranye,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_rounded, size: 19, color: WarnaTeras.oranye),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Pastikan pembayaran QRIS sudah berhasil di perangkat pelanggan '
            'sebelum menekan Sudah Bayar.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF5A5048),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 22),
    Row(
      children: [
        Expanded(
          child: TombolLembar(
            label: 'Batal',
            latar: const Color(0xFFD3D3D3),
            warna: WarnaTeras.teks,
            tinggi: 46,
            sudut: 6,
            ukuranTeks: 15,
            beratTeks: FontWeight.w500,
            onPressed: _memproses ? null : () => Navigator.pop(context, false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TombolLembar(
            label: _memproses ? 'Memproses…' : 'Sudah Bayar',
            latar: WarnaTeras.oranye,
            warna: Colors.white,
            tinggi: 46,
            sudut: 6,
            ukuranTeks: 15,
            beratTeks: FontWeight.w500,
            onPressed: _memproses ? null : _konfirmasi,
          ),
        ),
      ],
    ),
  ];
}
