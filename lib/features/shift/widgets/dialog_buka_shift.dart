import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';

/// Batas digit uang kas awal: sampai Rp999.999.999.
const digitMaksKasAwal = 9;

/// Nominal cepat di dialog Buka shift (desain).
const nominalCepatKasAwal = [100000, 200000, 300000, 500000];

/// Dialog "Buka shift" (desain): kasir mencatat uang tunai di laci. Hasil:
/// kas awal (boleh 0), atau null kalau batal.
Future<int?> tampilkanDialogBukaShift(
  BuildContext context, {
  required String nama,
}) => showDialog<int>(
  context: context,
  builder: (_) => _DialogBukaShift(nama: nama),
);

class _DialogBukaShift extends StatefulWidget {
  final String nama;

  const _DialogBukaShift({required this.nama});

  @override
  State<_DialogBukaShift> createState() => _DialogBukaShiftState();
}

class _DialogBukaShiftState extends State<_DialogBukaShift> {
  final _kas = TextEditingController();
  late final _jam = DateFormat('HH:mm').format(DateTime.now());
  String _galat = '';

  @override
  void dispose() {
    _kas.dispose();
    super.dispose();
  }

  int? get _nilai => parseRupiah(_kas.text);

  void _pilih(int nominal) => setState(() {
    _kas.text = formatRupiah(nominal);
    _galat = '';
  });

  void _buka() {
    final nilai = _nilai;
    if (nilai == null) {
      setState(() => _galat = 'Isi uang kas awal (boleh 0)');
      return;
    }
    Navigator.pop(context, nilai);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WarnaTeras.kartu,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: WarnaTeras.hijauMuda,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    size: 24,
                    color: WarnaTeras.hijau,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Buka shift',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WarnaTeras.teks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.nama} · $_jam',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WarnaTeras.teksPudar,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Uang kas awal',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5E5650),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Hitung uang tunai di laci sebelum mulai transaksi.',
              style: TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
            ),
            const SizedBox(height: 10),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  width: 1.5,
                  color: _galat.isNotEmpty
                      ? WarnaTeras.merah
                      : const Color(0xFFE6DED6),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'Rp',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _kas,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(digitMaksKasAwal),
                        RupiahInputFormatter(),
                      ],
                      onChanged: (_) => setState(() => _galat = ''),
                      onSubmitted: (_) => _buka(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: TextStyle(color: Color(0xFFB5ADA6)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              spacing: 6,
              children: [
                for (final n in nominalCepatKasAwal)
                  Expanded(child: _nominal(n)),
              ],
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 16),
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                _galat,
                style: const TextStyle(fontSize: 12, color: WarnaTeras.merah),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 10,
                  child: TombolLembar(
                    label: 'Batal',
                    latar: WarnaTeras.latarAbu,
                    warna: WarnaTeras.teks,
                    tinggi: 44,
                    sudut: 12,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 14,
                  child: TombolLembar(
                    label: 'Buka Shift',
                    latar: WarnaTeras.oranye,
                    warna: Colors.white,
                    tinggi: 44,
                    sudut: 12,
                    onPressed: _buka,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nominal(int n) {
    final dipilih = _nilai == n;
    return Material(
      color: dipilih ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: dipilih ? WarnaTeras.oranye : const Color(0xFFE6DED6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _pilih(n),
        child: SizedBox(
          height: 32,
          child: Center(
            child: Text(
              '${n ~/ 1000}rb',
              style: TextStyle(
                fontSize: TeksTeras.keterangan,
                fontWeight: FontWeight.w600,
                color: dipilih ? WarnaTeras.oranye : const Color(0xFF5A5048),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
