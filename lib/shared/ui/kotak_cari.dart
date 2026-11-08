import 'dart:async';

import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Kotak cari putih berbayang dengan ikon oranye dan tombol hapus (✕).
class KotakCari extends StatefulWidget {
  final String petunjuk;
  final ValueChanged<String> onBerubah;

  /// Halaman kasir memakai ukuran sedikit lebih besar (permintaan owner).
  final bool besar;

  /// Diisi: [onBerubah] baru dipanggil sesudah berhenti mengetik selama
  /// ini — untuk pencarian yang berat (Riwayat menyaring seluruh transaksi
  /// periode tiap ketukan; "nasi goreng" = 11 kali, review E1). Tombol ✕
  /// tetap langsung.
  final Duration? jeda;

  /// Kata cari yang sedang dipakai halaman. Kotak ini ada di dalam daftar
  /// yang digulir: begitu tergulir keluar layar ia dibuang, dan saat kembali
  /// dibuat ulang. Tanpa ini kotaknya tampil kosong padahal daftarnya masih
  /// tersaring (audit 6 Nov nomor 37).
  final String nilai;

  const KotakCari({
    super.key,
    required this.nilai,
    required this.onBerubah,
    this.petunjuk = 'Cari...',
    this.besar = false,
    this.jeda,
  });

  @override
  State<KotakCari> createState() => _KotakCariState();
}

class _KotakCariState extends State<KotakCari> {
  late final _c = TextEditingController(text: widget.nilai);
  Timer? _tunda;

  @override
  void dispose() {
    _tunda?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _kabari(String v) {
    _tunda?.cancel();
    final jeda = widget.jeda;
    if (jeda == null) {
      widget.onBerubah(v);
    } else {
      _tunda = Timer(jeda, () => widget.onBerubah(v));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.besar ? 50 : 48,
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
          Icon(
            Icons.search_rounded,
            size: widget.besar ? 24 : 22,
            color: WarnaTeras.oranye,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _c,
              onChanged: (v) {
                setState(() {});
                _kabari(v);
              },
              style: TextStyle(
                fontSize: widget.besar ? 15 : TeksTeras.biasa,
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
                _tunda?.cancel();
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
