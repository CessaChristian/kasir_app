import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Kotak cari putih berbayang dengan ikon oranye dan tombol hapus (✕).
class KotakCari extends StatefulWidget {
  final String petunjuk;
  final ValueChanged<String> onBerubah;

  const KotakCari({
    super.key,
    required this.onBerubah,
    this.petunjuk = 'Cari...',
  });

  @override
  State<KotakCari> createState() => _KotakCariState();
}

class _KotakCariState extends State<KotakCari> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C230A).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 22, color: WarnaTeras.oranye),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _c,
              onChanged: (v) {
                setState(() {});
                widget.onBerubah(v);
              },
              style: const TextStyle(
                fontSize: TeksTeras.biasa,
                color: WarnaTeras.teks,
              ),
              decoration: InputDecoration(
                hintText: widget.petunjuk,
                hintStyle: const TextStyle(color: Color(0xFFB5ADA6)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_c.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _c.clear();
                setState(() {});
                widget.onBerubah('');
              },
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: WarnaTeras.teksSamar,
              ),
            ),
        ],
      ),
    );
  }
}
