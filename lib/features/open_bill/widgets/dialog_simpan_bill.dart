import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/kolom_lembar.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../repositories/open_bill_repository.dart';

/// Dialog "Simpan Open Bill" / "Perbarui Open Bill" (desain): ringkasan
/// item + total, kolom Nama bill, [Batal] [Simpan].
///
/// [simpan] menyimpan dengan nama yang diketik dan mengembalikan pesan galat
/// (mis. "Nama sudah dipakai bill lain"), atau null kalau berhasil — galatnya
/// tampil di bawah kolom, dialog tetap terbuka. Hasil: nama yang tersimpan,
/// atau null kalau dibatalkan.
Future<String?> tanyaSimpanBill(
  BuildContext context, {
  required bool perbarui,
  required int jumlahItem,
  required int total,
  String namaAwal = '',
  required Future<String?> Function(String nama) simpan,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogSimpanBill(
      perbarui: perbarui,
      jumlahItem: jumlahItem,
      total: total,
      namaAwal: namaAwal,
      simpan: simpan,
    ),
  );
}

class _DialogSimpanBill extends StatefulWidget {
  final bool perbarui;
  final int jumlahItem;
  final int total;
  final String namaAwal;
  final Future<String?> Function(String nama) simpan;

  const _DialogSimpanBill({
    required this.perbarui,
    required this.jumlahItem,
    required this.total,
    required this.namaAwal,
    required this.simpan,
  });

  @override
  State<_DialogSimpanBill> createState() => _DialogSimpanBillState();
}

class _DialogSimpanBillState extends State<_DialogSimpanBill> {
  late final _nama = TextEditingController(text: widget.namaAwal);
  String? _galat;
  var _menyimpan = false;

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (_menyimpan) return;
    final nama = _nama.text.trim();
    if (nama.isEmpty) {
      setState(() => _galat = 'Nama bill wajib diisi');
      return;
    }
    setState(() => _menyimpan = true);
    final galat = await widget.simpan(nama);
    if (!mounted) return;
    if (galat == null) {
      Navigator.pop(context, nama);
    } else {
      setState(() {
        _menyimpan = false;
        _galat = galat;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final terisi = _nama.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: WarnaTeras.kartu,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: WarnaTeras.oranyeMuda,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bookmark_add_outlined,
                  size: 28,
                  color: WarnaTeras.oranye,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.perbarui ? 'Perbarui Open Bill' : 'Simpan Open Bill',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: WarnaTeras.teks,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: WarnaTeras.latar,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.jumlahItem} item',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF5A5048),
                      ),
                    ),
                  ),
                  Text(
                    formatRp(widget.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WarnaTeras.oranye,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            KolomLembar(
              label: 'Nama bill',
              controller: _nama,
              petunjuk: 'Contoh: Meja 3 · Andi',
              autofocus: true,
              galat: _galat != null,
              inputFormatters: [
                LengthLimitingTextInputFormatter(panjangMaksNamaBill),
              ],
              onChanged: (_) => setState(() => _galat = null),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                height: 18,
                child: Text(
                  _galat ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: WarnaTeras.merah),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 10,
                  child: TombolLembar(
                    label: 'Batal',
                    latar: WarnaTeras.latarAbu,
                    warna: WarnaTeras.teks,
                    tinggi: 46,
                    sudut: 12,
                    ukuranTeks: 15,
                    onPressed: _menyimpan ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 14,
                  child: TombolLembar(
                    label: 'Simpan',
                    latar: terisi ? WarnaTeras.oranye : const Color(0xFFF3D3B4),
                    warna: Colors.white,
                    tinggi: 46,
                    sudut: 12,
                    ukuranTeks: 15,
                    onPressed: _menyimpan ? null : _simpan,
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
