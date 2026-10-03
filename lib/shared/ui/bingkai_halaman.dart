import 'package:flutter/material.dart';

import 'header_teras.dart';
import 'segarkan/pengendali_segarkan.dart';
import 'segarkan/pita_sinkron.dart';
import 'segarkan/tombol_segarkan.dart';

/// Header + pita sinkron + isi halaman. Dipakai kerangka tab dan halaman
/// turunan, supaya tombol refresh dan perilakunya sama di mana pun.
///
/// Selama refresh berjalan isinya meredup dan tidak bisa disentuh, seperti
/// di desain: data yang sedang diganti tidak boleh diubah setengah jalan.
class BingkaiHalaman extends StatefulWidget {
  final String judul;
  final VoidCallback? onKembali;
  final Widget child;

  const BingkaiHalaman({
    super.key,
    required this.judul,
    required this.child,
    this.onKembali,
  });

  @override
  State<BingkaiHalaman> createState() => _BingkaiHalamanState();
}

class _BingkaiHalamanState extends State<BingkaiHalaman> {
  final _segarkan = PengendaliSegarkan();

  @override
  void dispose() {
    _segarkan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HeaderTeras(
          judul: widget.judul,
          onKembali: widget.onKembali,
          aksi: [TombolSegarkan(pengendali: _segarkan)],
        ),
        PitaSinkron(pengendali: _segarkan),
        Expanded(
          child: ListenableBuilder(
            listenable: _segarkan,
            builder: (context, isi) => IgnorePointer(
              ignoring: _segarkan.berjalan,
              child: AnimatedOpacity(
                opacity: _segarkan.berjalan ? 0.45 : 1,
                duration: const Duration(milliseconds: 250),
                child: isi,
              ),
            ),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
