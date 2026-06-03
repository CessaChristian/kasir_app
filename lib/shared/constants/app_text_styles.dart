import 'package:flutter/material.dart';

abstract class AppTextStyles {
  static const Color _darkText = Color(0xFF1A1A1A);

  static const TextStyle heading1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: _darkText,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
    color: _darkText,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: _darkText,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: _darkText,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    color: _darkText,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: Color(0xFF9E9E9E),
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Color(0xFF9E9E9E),
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
  );
}
