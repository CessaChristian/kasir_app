import 'package:flutter/material.dart';

class WatermarkBackground extends StatelessWidget {
  final Widget child;

  const WatermarkBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Watermark — di belakang konten
        Positioned.fill(
          child: Opacity(
            opacity: 0.50,
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/images/Neon Box 40x40cm (1).png',
                  width: 320,
                  height: 320,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        // Konten halaman — di atas watermark
        Positioned.fill(child: child),
      ],
    );
  }
}
