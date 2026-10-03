import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/shared/ui/bingkai_halaman.dart';
import 'package:kasir_app/shared/ui/header_teras.dart';

/// Bayangan tipis di bawah header muncul hanya saat isi sudah di-scroll.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  bool bayanganTerlihat(WidgetTester t) =>
      t.widget<BayanganHeader>(find.byType(BayanganHeader)).terlihat;
  bool bertepi(WidgetTester t) =>
      t.widget<HeaderTeras>(find.byType(HeaderTeras)).bertepi;

  Future<void> pasang(WidgetTester t, Widget isi) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BingkaiHalaman(judul: 'Uji', child: isi)),
        ),
      );

  testWidgets('muncul saat digulir ke bawah, hilang saat kembali ke atas',
      (t) async {
    await pasang(
      t,
      ListView(children: [
        for (var i = 0; i < 50; i++) SizedBox(height: 60, child: Text('$i')),
      ]),
    );
    expect(bayanganTerlihat(t), isFalse);
    expect(bertepi(t), isFalse);

    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(bayanganTerlihat(t), isTrue);
    expect(bertepi(t), isTrue);

    await t.drag(find.byType(ListView), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(bayanganTerlihat(t), isFalse);
  });

  testWidgets('geser ke samping (deretan chip) tidak menyalakan bayangan',
      (t) async {
    await pasang(
      t,
      SizedBox(
        height: 60,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < 30; i++) SizedBox(width: 80, child: Text('$i')),
        ]),
      ),
    );
    await t.drag(find.byType(ListView), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(bayanganTerlihat(t), isFalse);
  });
}
