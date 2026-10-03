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

  /// Isi sudah tergeser lebih dari 2px (ambang yang sama dengan desain).
  bool _tergulir = false;

  @override
  void didUpdateWidget(BingkaiHalaman lama) {
    super.didUpdateWidget(lama);
    // Pindah tab = isi baru yang mulai dari atas.
    if (lama.judul != widget.judul) _tergulir = false;
  }

  bool _dengarGulir(ScrollNotification n) {
    // Hanya gulir vertikal: deretan chip kategori yang digeser ke samping
    // tidak boleh menyalakan bayangan.
    if (n.metrics.axis != Axis.vertical) return false;
    final v = n.metrics.pixels > 2;
    if (v != _tergulir) setState(() => _tergulir = v);
    return false;
  }

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
          bertepi: _tergulir,
          aksi: [TombolSegarkan(pengendali: _segarkan)],
        ),
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  PitaSinkron(pengendali: _segarkan),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _dengarGulir,
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
                  ),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: BayanganHeader(terlihat: _tergulir),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
