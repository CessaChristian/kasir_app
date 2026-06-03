import 'package:flutter/material.dart';

enum ToastType { success, error, warning, info }

class AppToast {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

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

  (Color bg, Color border, Color icon, IconData defaultIcon) get _style {
    switch (widget.type) {
      case ToastType.success:
        return (
          const Color(0xFFE8F5E9),
          const Color(0xFFA5D6A7),
          Colors.green.shade700,
          Icons.check_circle_rounded,
        );
      case ToastType.error:
        return (
          const Color(0xFFFFEBEE),
          const Color(0xFFEF9A9A),
          Colors.red.shade600,
          Icons.error_rounded,
        );
      case ToastType.warning:
        return (
          const Color(0xFFFFF8E1),
          const Color(0xFFFFD54F),
          Colors.orange.shade700,
          Icons.warning_amber_rounded,
        );
      case ToastType.info:
        return (
          const Color(0xFFE3F2FD),
          const Color(0xFF90CAF9),
          Colors.blue.shade600,
          Icons.info_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, border, iconColor, defaultIcon) = _style;
    final usedIcon = widget.icon ?? defaultIcon;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(usedIcon, color: iconColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: iconColor,
                          height: 1.3,
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
