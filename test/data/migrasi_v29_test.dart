import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v29 SUNGGUHAN: kolom `products.barcode` dicopot atas
/// permintaan owner. Produknya — termasuk pilihan dan relasi kategorinya —
/// tidak boleh tersentuh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v29 mencopot products.barcode tanpa menyentuh produknya', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = Directory.systemTemp.createTempSync('uji_v29');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v28.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.categories).insert(CategoriesCompanion.insert(
          id: const Value('k-minum'),
          name: 'Minuman',
        ));
    await lama.into(lama.products).insert(ProductsCompanion.insert(
          id: const Value('p-es'),
          name: 'Es Kopi Susu',
          price: 14000,
          categoryId: const Value('k-minum'),
          hasIceOption: const Value(true),
        ));
    await lama.close();

    // Keadaan v28: kolom barcode masih ada, bahkan terisi.
    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
    mentah.execute("UPDATE products SET barcode = '899123'");
    mentah.execute('PRAGMA user_version = 28');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final kolom = await baru
        .customSelect("SELECT name FROM pragma_table_info('products')")
        .get();
    final p = await baru.select(baru.products).getSingle();
    await baru.close();

    expect(kolom.map((r) => r.read<String>('name')), isNot(contains('barcode')));
    expect(p.name, 'Es Kopi Susu');
    expect(p.categoryId, 'k-minum');
    expect(p.hasIceOption, isTrue);
  });
}
