import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/features/owner/widgets/lembar_kasir.dart';
import 'package:kasir_app/features/shift/widgets/dialog_buka_shift.dart';
import 'package:kasir_app/shared/ui/periode/lembar_periode.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';

/// Audit 6 Nov nomor 48: HP layar kecil dengan huruf diperbesar. Isi yang
/// tidak muat dulu terpotong (galat "overflowed" di test) dan tombolnya tidak
/// bisa diketuk.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  void layarKecil(WidgetTester t) {
    t.view.physicalSize = const Size(320, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget aplikasi(Widget Function(BuildContext) isi) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: Builder(builder: isi)),
      );

  testWidgets('lembar periode tidak terpotong', (t) async {
    layarKecil(t);
    await t.pumpWidget(aplikasi((c) => TextButton(
          onPressed: () => pilihPeriode(
            c,
            awal: Periode.hari(DateTime(2026, 11, 9)),
            hariIni: DateTime(2026, 11, 9),
          ),
          child: const Text('buka'),
        )));
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('Terapkan'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Terapkan').hitTestable(), findsOneWidget);
  });

  testWidgets('dialog Buka shift tidak terpotong saat keyboard terbuka',
      (t) async {
    layarKecil(t);
    // Keyboard angka menutup separuh layar.
    t.view.viewInsets = const FakeViewPadding(bottom: 240);
    await t.pumpWidget(aplikasi((c) => TextButton(
          onPressed: () => tampilkanDialogBukaShift(c, nama: 'sari'),
          child: const Text('buka'),
        )));
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('pesan galat panjang di Reset PIN turun ke baris berikutnya',
      (t) async {
    layarKecil(t);
    await t.pumpWidget(aplikasi((_) => Padding(
          padding: const EdgeInsets.all(16),
          child: pesanPin(
            'Tidak tersambung ke server. PIN belum tersimpan, periksa '
            'internet lalu coba lagi.',
            false,
          ),
        )));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
