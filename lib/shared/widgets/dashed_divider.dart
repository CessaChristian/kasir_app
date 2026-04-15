import 'package:flutter/material.dart';

/// Garis putus-putus untuk struk
class DashedDivider extends StatelessWidget {
  final Color? color;
  final int dashCount;

  const DashedDivider({
    super.key,
    this.color,
    this.dashCount = 30,
  });

  @override
  Widget build(BuildContext context) {
    final dashColor = color ?? Colors.grey.shade400;
    return Row(
      children: List.generate(
        dashCount,
        (index) => Expanded(
          child: Container(
            height: 1,
            color: index.isEven ? dashColor : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
