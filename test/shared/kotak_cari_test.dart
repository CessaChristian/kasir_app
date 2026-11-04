import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/kotak_cari.dart';

/// Review E1: pencarian Riwayat dulu menyaring ulang seluruh transaksi
/// periode di setiap huruf.
void main() {
  testWidgets('dengan jeda: dikabarkan sekali, sesudah berhenti mengetik',
      (t) async {
    final dikabari = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KotakCari(
          jeda: const Duration(milliseconds: 300),
          onBerubah: dikabari.add,
        ),
      ),
    ));
    for (final teks in ['n', 'na', 'nas', 'nasi']) {
      await t.enterText(find.byType(TextField), teks);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(dikabari, isEmpty, reason: 'masih mengetik');
    await t.pump(const Duration(milliseconds: 300));
    expect(dikabari, ['nasi']);

    // Tombol hapus tetap langsung.
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump();
    expect(dikabari.last, '');
  });
}
