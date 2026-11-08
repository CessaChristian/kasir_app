import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/products/pages/products_page.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/products/sheets/product_form_sheet.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 6 Nov nomor 39: kategori yang hilang dari HP ini.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> masukOwner(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(
      () => SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'o',
          username: 'owner',
          role: 'owner',
          shiftId: null,
          permissions: const [],
        ),
      ),
    );
  }

  Future<void> isi(WidgetTester t) => t.runAsync(() async {
        await db.into(db.categories).insert(
              CategoriesCompanion.insert(id: const Value('kopi'), name: 'Kopi'),
            );
        for (final (id, nama, kat) in [
          ('p1', 'Latte', 'kopi'),
          ('p2', 'Es Teh', null),
        ]) {
          await db.into(db.products).insert(
                ProductsCompanion.insert(
                  id: Value(id),
                  name: nama,
                  price: 5000,
                  categoryId: Value(kat),
                ),
              );
        }
      });

  Future<void> jalan(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('kategori terpilih dihapus: daftar kembali ke Semua', (t) async {
    await masukOwner(t);
    await isi(t);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductsPage(repo: ProductRepository(db))),
      ),
    );
    await jalan(t);
    await t.tap(find.text('Kopi').first);
    await jalan(t);
    expect(find.text('Es Teh'), findsNothing, reason: 'tersaring Kopi');

    // Dihapus dari HP lain: tarikan menandai kategori terhapus dan
    // melepasnya dari produk.
    // Tanpa runAsync: database ini dipakai halaman yang sedang mengamati,
    // dan menulis dari zona lain membuat test macet.
    await (db.update(db.categories)..where((c) => c.id.equals('kopi')))
        .write(CategoriesCompanion(deletedAt: Value(DateTime.now())));
    await (db.update(db.products)..where((p) => p.id.equals('p1')))
        .write(const ProductsCompanion(categoryId: Value(null)));
    await jalan(t);
    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('Es Teh'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'form edit: kategori yang tidak ada di HP ini tidak ikut dikosongkan',
      (t) async {
    await isi(t);
    // Produk menunjuk kategori yang sudah tidak tampil di HP ini (mis. baru
    // dihapus, lepasnya belum sampai).
    await t.runAsync(
      () => (db.update(db.categories)..where((c) => c.id.equals('kopi')))
          .write(CategoriesCompanion(deletedAt: Value(DateTime.now()))),
    );
    final latte = await t.runAsync(
      () => (db.select(db.products)..where((p) => p.id.equals('p1')))
          .getSingle(),
    );
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FormResult? hasil;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<FormResult>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProductFormSheet(
                editing: latte,
                simpan: (h) async => hasil = h,
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
    await t.enterText(find.byType(TextField).at(1), '6000');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Simpan Perubahan'));
    await jalan(t);
    expect(hasil?.price, 6000);
    expect(hasil?.categoryId, 'kopi');

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
