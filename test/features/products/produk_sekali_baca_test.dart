import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/products/pages/products_page.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Penghitung extends ProductRepository {
  _Penghitung(super.db);
  var produk = 0;
  var kategori = 0;

  @override
  Stream<List<Product>> watchProducts() {
    produk++;
    return super.watchProducts();
  }

  @override
  Stream<List<Category>> watchCategories() {
    kategori++;
    return super.watchCategories();
  }
}

/// Review E4: tiap huruf di kotak cari dulu memasang ulang pengamatan
/// produk dan kategori, jadi kuerinya jalan ulang terus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mengetik di kotak cari tidak membaca ulang data', (t) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await SessionManager.instance.clearSession();
      await db.close();
    });
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
    final repo = _Penghitung(db);
    Future<void> jalan() async {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 400));
    }

    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: ProductsPage(repo: repo))),
    );
    await jalan();
    expect(repo.produk, 1);
    expect(repo.kategori, 1);

    for (final kata in ['g', 'go', 'gor']) {
      await t.enterText(find.byType(TextField), kata);
      await jalan();
    }
    expect(repo.produk, 1);
    expect(repo.kategori, 1);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
