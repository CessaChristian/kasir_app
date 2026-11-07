import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/crypto_utils.dart';
import '../../../utils/pesan_galat.dart';

/// PIN owner yang dikirim ke server ternyata salah.
class PinOwnerSalah extends StateError {
  PinOwnerSalah() : super('PIN owner salah.');
}

/// Lembar "masukkan PIN owner" untuk aksi perangkat (Cabut, Pulihkan,
/// Lupakan). PIN-nya diperiksa SERVER, bukan HP ini (audit 6 Nov nomor 1):
/// HP yang diakali tidak bisa mencabut HP lain tanpa tahu PIN owner. Owner
/// tetap bisa melakukannya dari HP mana pun.
///
/// [aksi] dijalankan di dalam lembar. True kalau berhasil; PIN salah atau
/// galat lain tampil di lembar supaya bisa dicoba lagi.
Future<bool> tanyaPinOwnerLalu(
  BuildContext context, {
  required IconData ikon,
  required String judul,
  required String catatan,
  required String labelAksi,
  required Future<void> Function(String pin) aksi,
}) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LembarPinOwner(
      ikon: ikon,
      judul: judul,
      catatan: catatan,
      labelAksi: labelAksi,
      aksi: aksi,
    ),
  );
  return hasil ?? false;
}

class LembarPinOwner extends StatefulWidget {
  final IconData ikon;
  final String judul;
  final String catatan;
  final String labelAksi;
  final Future<void> Function(String pin) aksi;

  const LembarPinOwner({
    super.key,
    required this.ikon,
    required this.judul,
    required this.catatan,
    required this.labelAksi,
    required this.aksi,
  });

  @override
  State<LembarPinOwner> createState() => _LembarPinOwnerState();
}

class _LembarPinOwnerState extends State<LembarPinOwner> {
  final _pinC = TextEditingController();
  var _memproses = false;
  String? _galat;

  @override
  void dispose() {
    _pinC.dispose();
    super.dispose();
  }

  Future<void> _kirim() async {
    if (_memproses) return;
    if (_pinC.text.length != CryptoUtils.pinLength) {
      setState(() => _galat = 'PIN harus ${CryptoUtils.pinLength} angka');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      await widget.aksi(_pinC.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memproses = false;
        _galat = e is PinOwnerSalah
            ? e.message
            : pesanGalat(e, awalan: 'Gagal ${widget.labelAksi.toLowerCase()}');
        _pinC.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Selama dikirim tidak bisa ditutup: hasilnya harus terlihat.
      canPop: !_memproses,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: WarnaTeras.merahMuda,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(widget.ikon, size: 30, color: WarnaTeras.merah),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.judul,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TeksTeras.judulBagian,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.catatan,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TeksTeras.biasa,
                color: WarnaTeras.teksPudar,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('isian-pin-owner'),
              controller: _pinC,
              autofocus: true,
              obscureText: true,
              enabled: !_memproses,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(CryptoUtils.pinLength),
              ],
              onChanged: (_) => setState(() => _galat = null),
              onSubmitted: (_) => _kirim(),
              style: const TextStyle(fontSize: TeksTeras.angka, letterSpacing: 6),
              decoration: InputDecoration(
                labelText: 'PIN owner',
                errorText: _galat,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _memproses ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _memproses ? null : _kirim,
                    style: FilledButton.styleFrom(
                      backgroundColor: WarnaTeras.merah,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_memproses ? 'Memeriksa…' : widget.labelAksi),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
