import 'package:flutter/material.dart';

/// Indikator loading standar app. Gunakan ini menggantikan
/// `Center(child: CircularProgressIndicator(...))` yang tersebar.
class LoadingIndicator extends StatelessWidget {
  final Color? color;
  final double strokeWidth;
  final bool center;

  const LoadingIndicator({
    super.key,
    this.color,
    this.strokeWidth = 2.5,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(
      color: color ?? Theme.of(context).colorScheme.primary,
      strokeWidth: strokeWidth,
    );
    return center ? Center(child: indicator) : indicator;
  }
}
