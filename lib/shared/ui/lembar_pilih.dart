import 'package:flutter/material.dart';

import 'pegang_lembar.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// Satu baris di [pilihDariDaftar].
class OpsiLembar<T> {
  final T nilai;
  final String label;
  final IconData ikon;

  const OpsiLembar({
    required this.nilai,
    required this.label,
    required this.ikon,
  });
}

/// Hasil [pilihDariDaftar]: [nilai] boleh null (mis. "Tanpa Kategori"), jadi
/// "tidak memilih apa-apa" dibedakan dengan record yang null.
typedef HasilPilih<T> = ({T nilai});

/// Lembar pilih dari bawah (desain "Pilih Kategori"): judul berikon, daftar
/// ikon + label, tanda ✓ pada yang terpilih. Null kalau ditutup tanpa memilih.
Future<HasilPilih<T>?> pilihDariDaftar<T>(
  BuildContext context, {
  required String judul,
  required IconData ikon,
  required List<OpsiLembar<T>> opsi,
  required T terpilih,
}) {
  return showModalBottomSheet<HasilPilih<T>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: WarnaTeras.kartu,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PegangLembar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WarnaTeras.oranye,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(ikon, size: 21, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  judul,
                  style: const TextStyle(
                    fontSize: TeksTeras.menu,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teks,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in opsi) _baris(context, o, o.nilai == terpilih),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _baris<T>(BuildContext context, OpsiLembar<T> o, bool aktif) {
  return Material(
    color: aktif ? const Color(0xFFFAF3EC) : Colors.transparent,
    child: InkWell(
      onTap: () => Navigator.pop(context, (nilai: o.nilai)),
      child: SizedBox(
        height: 54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: aktif
                      ? const Color(0xFFFDE3C8)
                      : const Color(0xFFE4E2E0),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  o.ikon,
                  size: 18,
                  color: aktif ? WarnaTeras.oranye : const Color(0xFF5A5048),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    color: aktif ? WarnaTeras.oranye : const Color(0xFF5A5048),
                  ),
                ),
              ),
              if (aktif)
                const Icon(
                  Icons.check_rounded,
                  size: 21,
                  color: WarnaTeras.oranye,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
