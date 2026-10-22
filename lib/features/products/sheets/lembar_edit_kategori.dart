import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/constants/category_icons.dart';
import '../../../shared/ui/kolom_lembar.dart';
import '../../../shared/ui/lembar_bawah.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../pages/kategori_page.dart' show panjangNamaKategori;
import '../widgets/pilihan_ikon_kategori.dart';

/// Hasil lembar Edit Kategori: nama (sudah dirapikan) dan codepoint ikon.
typedef HasilEditKategori = ({String nama, int? ikon});

/// Lembar "Edit Kategori" (desain): kisi ikon, kolom Nama kategori,
/// [Batal] [Simpan]. [periksa] mengembalikan galat nama (kosong, kembar)
/// atau null. Hasil: null kalau dibatalkan.
///
/// Ikon lama yang tidak ada di pilihan (dibuat versi aplikasi sebelumnya)
/// tetap dipakai selama kasir tidak memilih ikon lain.
Future<HasilEditKategori?> tampilkanEditKategori(
  BuildContext context, {
  required String nama,
  required int? ikon,
  required String? Function(String nama) periksa,
}) async {
  final hasil = await tampilkanLembarBawah<Object>(
    context,
    (_) => _LembarEditKategori(nama: nama, ikon: ikon, periksa: periksa),
  );
  return hasil is HasilEditKategori ? hasil : null;
}

class _LembarEditKategori extends StatefulWidget {
  final String nama;
  final int? ikon;
  final String? Function(String nama) periksa;

  const _LembarEditKategori({
    required this.nama,
    required this.ikon,
    required this.periksa,
  });

  @override
  State<_LembarEditKategori> createState() => _LembarEditKategoriState();
}

class _LembarEditKategoriState extends State<_LembarEditKategori> {
  late final _nama = TextEditingController(text: widget.nama);
  late IconData _ikon = categoryIconFromCodepoint(widget.ikon);
  var _ikonDiganti = false;
  String _galat = '';

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  void _simpan() {
    final nama = _nama.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final galat = widget.periksa(nama);
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    Navigator.pop<HasilEditKategori>(context, (
      nama: nama,
      ikon: _ikonDiganti ? _ikon.codePoint : widget.ikon,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Text(
          'Edit Kategori',
          style: TextStyle(
            fontSize: TeksTeras.judulBagian,
            fontWeight: FontWeight.w700,
            color: WarnaTeras.teks,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ikon',
          style: TextStyle(fontSize: 13, color: WarnaTeras.teksPudar),
        ),
        const SizedBox(height: 8),
        PilihanIkonKategori(
          terpilih: _ikon,
          ukuran: 42,
          ukuranIkon: 24,
          jarak: 9,
          sudut: 11,
          onPilih: (ikon) => setState(() {
            _ikon = ikon;
            _ikonDiganti = true;
          }),
        ),
        const SizedBox(height: 18),
        KolomLembar(
          label: 'Nama kategori',
          controller: _nama,
          ikon: _ikon,
          petunjuk: 'Nama kategori',
          galat: _galat.isNotEmpty,
          inputFormatters: [
            LengthLimitingTextInputFormatter(panjangNamaKategori),
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
