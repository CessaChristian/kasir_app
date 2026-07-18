import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/db.dart';

void main() {
  // Regression test: top-level variable di Dart bersifat lazy, sehingga
  // wiring BusinessContext -> AppDatabase yang ditaruh di variabel terpisah
  // tidak pernah dieksekusi. Akibatnya semua watch method mengembalikan
  // Stream.empty() dan halaman Produk/Riwayat stuck loading selamanya.
  test('mengakses db otomatis wire activeBusinessIdProvider', () {
    expect(db, isA<AppDatabase>());
    expect(
      AppDatabase.hasActiveBusinessProvider,
      isTrue,
      reason: 'activeBusinessIdProvider harus ter-set saat db diakses, '
          'kalau tidak semua watch method return Stream.empty()',
    );
  });
}
