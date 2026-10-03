import 'package:flutter/material.dart';

import '../ui/teks_teras.dart';
import '../ui/warna_teras.dart';

enum ToastType { success, error, warning, info }

class AppToast {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    IconData? icon,
    // Desain: tampil 2,2 detik.
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    if (!context.mounted) return;

    _activeEntry?.remove();
    _activeEntry = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        type: type,
        icon: icon,
        duration: duration,
        onFinished: () {
          try {
            entry.remove();
          } catch (_) {}
          if (_activeEntry == entry) _activeEntry = null;
        },
      ),
    );

    overlay.insert(entry);
    _activeEntry = entry;
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.success);

  static void error(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.error);

  static void warning(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message: message, type: ToastType.info);
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final ToastType type;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onFinished;

  const _ToastOverlay({
    required this.message,
    required this.type,
    this.icon,
    required this.duration,
    required this.onFinished,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  /// Gerak masuk desain: `cubic-bezier(.32,.72,0,1)` — cepat lalu mengendap.
  static const _kurva = Cubic(.32, .72, 0, 1);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 300),
    );
    // Naik dari bawah (desain), bukan turun dari atas.
    _slide = Tween<Offset>(
      begin: const Offset(0, 1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: _kurva));
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 300 / 420, curve: Curves.ease),
    );

    _ctrl.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onFinished();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// (latar ikon, warna ikon, ikon bawaan). Kartunya selalu putih.
  (Color, Color, IconData) get _gaya => switch (widget.type) {
        ToastType.success => (
            WarnaTeras.hijauMuda,
            WarnaTeras.hijau,
            Icons.check_circle_rounded,
          ),
        ToastType.info => (
            WarnaTeras.oranyeMuda,
            WarnaTeras.oranye,
            Icons.info_rounded,
          ),
        ToastType.warning => (
            WarnaTeras.merahMuda,
            WarnaTeras.merah,
            Icons.warning_rounded,
          ),
        ToastType.error => (
            WarnaTeras.merahMuda,
            WarnaTeras.merah,
            Icons.error_rounded,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (latarIkon, warnaIkon, ikonBawaan) = _gaya;
    final mq = MediaQuery.of(context);
    // Di atas nav bawah (tinggi 66) — atau di atas keyboard kalau terbuka.
    final bawah = (mq.viewInsets.bottom > 0
            ? mq.viewInsets.bottom
            : mq.padding.bottom + 66) +
        12;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bawah,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                decoration: BoxDecoration(
                  color: WarnaTeras.kartu,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF3C230A).withValues(alpha: 0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3C230A).withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: latarIkon,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(widget.icon ?? ikonBawaan,
                          size: 19, color: warnaIkon),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: TeksTeras.biasa,
                          color: WarnaTeras.teks,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
