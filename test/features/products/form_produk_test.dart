import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/products/sheets/product_form_sheet.dart';

/// Form produk baru tertutup sesudah tersimpan. Dulu tertutup duluan: nama
/// kembar ditolak sesudahnya dan semua isian hilang (audit nomor 7 & 8).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Bukan pumpAndSettle: aliran database dan toast tidak pernah "tenang".
  Future<void> jalan(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> buka(
    WidgetTester t,
    Future<void> Function(FormResult) simpan,
  ) async {
    // Lebar sekali: huruf uji jauh lebih lebar dari huruf aslinya.
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<FormResult>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProductFormSheet(
                simpan: simpan,
                repo: ProductRepository(db),
              ),
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await jalan(t);
    await t.enterText(find.byType(TextField).at(0), 'Es Teh');
    await t.enterText(find.byType(TextField).at(1), '5000');
    await t.pump();
  }

  Finder tombol() => find.widgetWithText(FilledButton, 'Tambah Produk');

  testWidgets('nama kembar: toast muncul, form dan isiannya tetap ada', (
    t,
  ) async {
    await buka(t, (_) async {
      throw StateError('Produk bernama "Es Teh" sudah ada.');
    });
    await t.tap(tombol());
    await jalan(t);

    expect(find.text('Produk bernama "Es Teh" sudah ada.'), findsOneWidget);
    expect(find.byType(ProductFormSheet), findsOneWidget);
    expect(find.text('Es Teh'), findsOneWidget);
    expect(tombol(), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('berhasil: form tertutup', (t) async {
    FormResult? tersimpan;
    await buka(t, (h) async => tersimpan = h);
    await t.tap(tombol());
    await jalan(t);
    expect(tersimpan?.name, 'Es Teh');
    expect(find.byType(ProductFormSheet), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
