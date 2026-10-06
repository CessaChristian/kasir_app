import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/kategori_biaya.dart';

/// Isian dialog Pengeluaran. [amount] adalah TOTAL (nominal × [qty]).
class InputPengeluaran {
  final String keterangan;
  final int amount;
  final KategoriBiaya kategori;
  final int qty;

  const InputPengeluaran({
    required this.keterangan,
    required this.amount,
    required this.kategori,
    required this.qty,
  });
}

/// Pesan galat dialog Pengeluaran (desain), atau null kalau sah.
String? galatFormPengeluaran({
  required String keterangan,
  required String nominalTeks,
  String jumlahTeks = '1',
}) {
  if (keterangan.trim().isEmpty) return 'Keterangan wajib diisi';
  final n = parseRupiah(nominalTeks);
  if (n == null || n <= 0) return 'Nominal wajib diisi';
  final q = int.tryParse(jumlahTeks.trim());
  if (q == null || q < 1) return 'Jumlah minimal 1';
  return null;
}

/// Dialog "Pengeluaran" (desain): Kategori Biaya · Keterangan · Nominal ·
/// Jumlah, lalu Batal / Simpan. Hanya mengumpulkan isian — penyimpanan
/// dilakukan pemanggil SETELAH dialog tertutup.
Future<InputPengeluaran?> tampilkanDialogPengeluaran(
  BuildContext context, {
  required String subjudul,
}) {
  return showDialog<InputPengeluaran>(
    context: context,
    barrierColor: const Color(0x66281909),
    builder: (_) => _DialogPengeluaran(subjudul: subjudul),
  );
}

class _DialogPengeluaran extends StatefulWidget {
  final String subjudul;

  const _DialogPengeluaran({required this.subjudul});

  @override
  State<_DialogPengeluaran> createState() => _DialogPengeluaranState();
}

class _DialogPengeluaranState extends State<_DialogPengeluaran> {
  final _keteranganC = TextEditingController();
  final _nominalC = TextEditingController();
  final _nominalFokus = FocusNode();
  var _kategori = KategoriBiaya.bahanBaku; // bawaan desain
  /// Jumlah bisa diketik langsung; panah ▼▲ menambah/mengurangi isinya.
  final _jumlahC = TextEditingController(text: '1');

  int get _qty => int.tryParse(_jumlahC.text) ?? 0;

  void _geserJumlah(int d) => setState(() {
    final baru = (_qty + d).clamp(1, _jumlahMaks);
    _jumlahC.text = '$baru';
    _galat = null;
  });

  static const _jumlahMaks = 9999;
  String? _galat;

  @override
  void initState() {
    super.initState();
    // "Rp" muncul/hilang mengikuti fokus — lihat isian Nominal.
    _nominalFokus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nominalFokus.dispose();
    _jumlahC.dispose();
    _keteranganC.dispose();
    _nominalC.dispose();
    super.dispose();
  }

  void _simpan() {
    final galat = galatFormPengeluaran(
      keterangan: _keteranganC.text,
      nominalTeks: _nominalC.text,
      jumlahTeks: _jumlahC.text,
    );
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    Navigator.pop(
      context,
      InputPengeluaran(
        keterangan: _keteranganC.text.trim(),
        amount: parseRupiah(_nominalC.text)! * _qty,
        kategori: _kategori,
        qty: _qty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WarnaTeras.kartu,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranye,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pengeluaran',
                      style: TextStyle(
                        fontSize: TeksTeras.menu,
                        fontWeight: FontWeight.w600,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    Text(
                      widget.subjudul,
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksSamar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Kategori Biaya',
                    style: TextStyle(
                      fontSize: TeksTeras.biasa,
                      color: WarnaTeras.teksPudar,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final k in KategoriBiaya.values) _chip(k)],
                  ),
                  const SizedBox(height: 14),
                  _isian(
                    ikon: Icons.description_outlined,
                    child: TextField(
                      controller: _keteranganC,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() => _galat = null),
                      style: _gayaIsian,
                      decoration: _hias('Keterangan pengeluaran'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _isian(
                    ikon: Icons.payments_outlined,
                    // "Rp" dibuat sendiri, BUKAN prefixText: prefixText
                    // menyisakan ruang kosong saat belum diklik (petunjuk
                    // jadi tidak sejajar dengan isian di atasnya) dan
                    // menyembunyikan petunjuk "Nominal" begitu diklik.
                    child: Row(
                      children: [
                        if (_nominalFokus.hasFocus || _nominalC.text.isNotEmpty)
                          const Text('Rp ', style: _gayaIsian),
                        Expanded(
                          child: TextField(
                            controller: _nominalC,
                            focusNode: _nominalFokus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              RupiahInputFormatter(),
                            ],
                            onChanged: (_) => setState(() => _galat = null),
                            style: _gayaIsian,
                            decoration: _hias('Nominal'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _isian(
                    ikon: Icons.tag_rounded,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('isian-jumlah'),
                            controller: _jumlahC,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              // Panjang ketikan mengikuti batas jumlah (9999 → 4 digit).
                              LengthLimitingTextInputFormatter(
                                '$_jumlahMaks'.length,
                              ),
                            ],
                            onChanged: (_) => setState(() => _galat = null),
                            style: _gayaIsian,
                            decoration: _hias('Jumlah'),
                          ),
                        ),
                        // Bertumpuk ▲/▼ seperti desain. Tiap panah 36×22
                        // supaya mudah diketuk; keduanya muat di kotak 50 px.
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _panah(
                              Icons.arrow_drop_up_rounded,
                              'Tambah jumlah',
                              _qty < _jumlahMaks ? () => _geserJumlah(1) : null,
                            ),
                            _panah(
                              Icons.arrow_drop_down_rounded,
                              'Kurangi jumlah',
                              _qty > 1 ? () => _geserJumlah(-1) : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _galat ?? '',
                        style: const TextStyle(
                          fontSize: TeksTeras.kecil,
                          color: WarnaTeras.merah,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TombolLembar(
                          label: 'Batal',
                          latar: const Color(0xFFE6E1DC),
                          warna: WarnaTeras.teks,
                          tinggi: _tinggiTombol,
                          sudut: _sudutTombol,
                          ukuranTeks: TeksTeras.menu,
                          beratTeks: FontWeight.w500,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TombolLembar(
                          label: 'Simpan',
                          latar: WarnaTeras.oranye,
                          warna: Colors.white,
                          tinggi: _tinggiTombol,
                          sudut: _sudutTombol,
                          ukuranTeks: TeksTeras.menu,
                          beratTeks: FontWeight.w500,
                          onPressed: _simpan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _gayaIsian = TextStyle(
    fontSize: TeksTeras.angka,
    color: WarnaTeras.teks,
  );

  InputDecoration _hias(String petunjuk) => InputDecoration(
    hintText: petunjuk,
    hintStyle: const TextStyle(color: Color(0xFFB5ADA6)),
    border: InputBorder.none,
    isDense: true,
    contentPadding: EdgeInsets.zero,
  );

  Widget _isian({required IconData ikon, required Widget child}) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFBDB6AF)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(ikon, size: 22, color: WarnaTeras.oranye),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _chip(KategoriBiaya k) {
    final aktif = _kategori == k;
    return GestureDetector(
      onTap: () => setState(() => _kategori = k),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: aktif ? WarnaTeras.oranye : const Color(0xFFD3D3D3),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          k.label,
          style: TextStyle(
            fontSize: TeksTeras.biasa,
            color: aktif ? Colors.white : WarnaTeras.teks,
          ),
        ),
      ),
    );
  }

  Widget _panah(IconData ikon, String label, VoidCallback? onTap) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 36,
          height: 22,
          child: OverflowBox(
            maxHeight: 30,
            child: Icon(
              ikon,
              size: 30,
              color: onTap == null ? WarnaTeras.garis : WarnaTeras.teksPudar,
            ),
          ),
        ),
      ),
    );
  }

  // Desain dialog ini: tinggi 44, sudut 8, huruf 15 medium.
  static const _tinggiTombol = 46.0;
  static const _sudutTombol = 8.0;
}
