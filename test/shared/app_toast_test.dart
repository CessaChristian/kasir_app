import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/widgets/app_toast.dart';

/// Toast mengikuti desain: kartu putih di BAWAH (di atas nav), naik dari
/// bawah, tampil ±2,2 detik lalu hilang.
void main() {
  testWidgets('muncul di bawah, lalu hilang sendiri', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => AppToast.success(context, 'Bill disimpan'),
          child: const Text('tampilkan'),
        ),
      ),
    ));
    await t.tap(find.text('tampilkan'));
    await t.pumpAndSettle(const Duration(milliseconds: 500));

    final kotak = t.getRect(find.text('Bill disimpan'));
    expect(kotak.center.dy, greaterThan(800 * 0.75),
        reason: 'toast di bagian bawah layar, bukan atas');

    await t.pump(const Duration(milliseconds: 2200));
    await t.pumpAndSettle();
    expect(find.text('Bill disimpan'), findsNothing);
  });
}
