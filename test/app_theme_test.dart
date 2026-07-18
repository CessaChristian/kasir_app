import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/app/app_theme.dart';

void main() {
  test('seed per tipe business', () {
    expect(seedForBusinessType('restaurant_dinein'), const Color(0xFFEE8A34));
    expect(seedForBusinessType('beverage_grabandgo'), const Color(0xFF212121));
    expect(seedForBusinessType(null), const Color(0xFFEE8A34));
  });

  test('buildAppTheme derive dari seed', () {
    final t = buildAppTheme(const Color(0xFF212121));
    expect(t.scaffoldBackgroundColor, isNot(Colors.white));
    expect(t.colorScheme.primary, const Color(0xFF212121));
  });
}
