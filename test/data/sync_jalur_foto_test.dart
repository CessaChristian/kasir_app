import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';

/// `image_path` yang tidak sah dibuang saat keluar-masuk server, supaya nilai
/// seperti `kasir_app.sqlite` tidak pernah sampai ke baris produk (audit no. 9).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mesin = SyncEngine(db);
  });
  tearDown(() => db.close());

  Map<String, dynamic> baris(String id, String? foto) => {
    'id': id,
    'name': 'Produk $id',
    'price': 5000,
    'category_id': null,
    'has_spicy_option': false,
    'image_path': foto,
    'created_at': '2026-09-01T00:00:00+00:00',
    'updated_at': '2026-09-02T00:00:00+00:00',
    'deleted_at': null,
    'server_urut': '2026-09-02T00:00:00+00:00',
  };

  Future<String?> fotoLokal(String id) async =>
      (await (db.select(db.products)..where((p) => p.id.equals(id)))
              .getSingle())
          .imagePath;

  test('tarikan: jalur jahat jadi kosong, jalur sah tetap', () async {
    await mesin.gabungkanTabel('products', [
      baris('jahat', 'kasir_app.sqlite'),
      baris('mutlak', '/data/user/0/id.terasinn.kasir/kasir_app.sqlite'),
      baris('sah', 'products/abc-1.webp'),
    ]);
    expect(await fotoLokal('jahat'), isNull);
    expect(await fotoLokal('mutlak'), isNull);
    expect(await fotoLokal('sah'), 'products/abc-1.webp');
  });

  test('kiriman: jalur jahat tidak ikut terkirim', () async {
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: const Value('jahat'),
        name: 'A',
        price: 1,
        imagePath: const Value('../kasir_app.sqlite'),
        syncStatus: const Value('pending'),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: const Value('sah'),
        name: 'B',
        price: 1,
        imagePath: const Value('products/abc-2.jpg'),
        syncStatus: const Value('pending'),
      ),
    );
    final terkirim = <String, Object?>{};
    mesin.pengirimUntukTest = (tabel, isi) async {
      if (tabel != 'products') return;
      for (final b in isi) {
        terkirim[b['id'] as String] = b['image_path'];
      }
    };
    await mesin.dorongSemua();
    expect(terkirim['jahat'], isNull);
    expect(terkirim['sah'], 'products/abc-2.jpg');
  });
}
