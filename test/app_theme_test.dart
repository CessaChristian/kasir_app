import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/app/app_theme.dart';

void main() {
  test('buildAppTheme derive dari seed', () {
    final t = buildAppTheme(kSeedDineIn);
    expect(t.scaffoldBackgroundColor, isNot(Colors.white));
    expect(t.colorScheme.primary, kSeedDineIn);
  });
}
