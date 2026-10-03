import 'package:flutter/material.dart';

import '../warna_teras.dart';
import 'pengendali_segarkan.dart';

/// Ikon ⟳ oranye di header. Berputar selama sinkron berjalan.
class TombolSegarkan extends StatefulWidget {
  final PengendaliSegarkan pengendali;

  const TombolSegarkan({super.key, required this.pengendali});

  @override
  State<TombolSegarkan> createState() => _TombolSegarkanState();
}

class _TombolSegarkanState extends State<TombolSegarkan>
    with SingleTickerProviderStateMixin {
  late final _putar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    widget.pengendali.addListener(_ikuti);
  }

  void _ikuti() {
    if (widget.pengendali.berjalan) {
      _putar.repeat();
    } else {
      // Selesaikan putaran yang sedang berjalan, jangan berhenti di tengah.
      _putar.forward(from: _putar.value).then((_) => _putar.reset());
    }
  }

  @override
  void dispose() {
    widget.pengendali.removeListener(_ikuti);
    _putar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.pengendali.segarkan,
      tooltip: 'Segarkan',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: RotationTransition(
        turns: _putar,
        child: const Icon(
          Icons.refresh_rounded,
          size: 24,
          color: WarnaTeras.oranye,
        ),
      ),
    );
  }
}
