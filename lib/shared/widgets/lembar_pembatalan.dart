import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../utils/crypto_utils.dart';

/// Lembar pembatalan yang dipakai bersama transaksi dan pengeluaran.
///
/// Pilih alasan, dan — kalau [perluPin] — masukkan PIN. Tulisan PIN sengaja
/// tidak menyebut PIN siapa. Kesalahan dari [kirim] (PIN salah, terkunci)
/// ditampilkan di dalam lembar supaya kasir bisa mencoba lagi tanpa memilih
/// ulang alasannya.
///
/// Mengembalikan true kalau pembatalan berhasil.
Future<bool> tampilkanLembarPembatalan(
  BuildContext context, {
  required String judul,
  required String keterangan,
  required List<String> daftarAlasan,
  required bool perluPin,
  required Future<void> Function(String alasan, String? pin) kirim,
}) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LembarPembatalan(
      judul: judul,
      keterangan: keterangan,
      daftarAlasan: daftarAlasan,
      perluPin: perluPin,
      kirim: kirim,
    ),
  );
  return hasil == true;
}

/// Alasan yang mewajibkan isian teks.
const alasanLainnya = 'Lainnya';

class _LembarPembatalan extends StatefulWidget {
  final String judul;
  final String keterangan;
  final List<String> daftarAlasan;
  final bool perluPin;
  final Future<void> Function(String alasan, String? pin) kirim;

  const _LembarPembatalan({
    required this.judul,
    required this.keterangan,
    required this.daftarAlasan,
    required this.perluPin,
    required this.kirim,
  });

  @override
  State<_LembarPembatalan> createState() => _LembarPembatalanState();
}

class _LembarPembatalanState extends State<_LembarPembatalan> {
  /// Panjang maksimal alasan "Lainnya".
  static const _panjangAlasanMaks = 100;

  final _pinC = TextEditingController();
  final _lainnyaC = TextEditingController();
  String? _alasan;
  String? _galat;
  var _memproses = false;

  @override
  void dispose() {
    _pinC.dispose();
    _lainnyaC.dispose();
    super.dispose();
  }

  String get _teksAlasan =>
      _alasan == alasanLainnya ? _lainnyaC.text.trim() : (_alasan ?? '');

  bool get _siap =>
      _teksAlasan.isNotEmpty &&
      (!widget.perluPin || _pinC.text.length == CryptoUtils.pinLength) &&
      !_memproses;

  Future<void> _kirim() async {
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      await widget.kirim(
        _alasan == alasanLainnya ? '$alasanLainnya: $_teksAlasan' : _teksAlasan,
        widget.perluPin ? _pinC.text : null,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (e) {
      _pinC.clear();
      setState(() {
        _memproses = false;
        _galat = e.message;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _memproses = false;
        _galat = '${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.judul,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(widget.keterangan,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          const Text('Alasan', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in widget.daftarAlasan)
                ChoiceChip(
                  label: Text(a),
                  selected: _alasan == a,
                  onSelected: (_) => setState(() => _alasan = a),
                ),
            ],
          ),
          if (_alasan == alasanLainnya) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _lainnyaC,
              maxLength: _panjangAlasanMaks,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Tulis alasannya',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (widget.perluPin) ...[
            const SizedBox(height: 16),
            const Text('Masukkan PIN',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _pinC,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: CryptoUtils.pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '• • • • • •',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
          if (_galat != null) ...[
            const SizedBox(height: 8),
            Text(_galat!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _siap ? _kirim : null,
              child: Text(_memproses ? 'Memproses…' : widget.judul),
            ),
          ),
        ],
      ),
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
    final kapan = DateFormat('dd/MM/yyyy HH:mm').format(dibatalkanPada.toLocal());
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
