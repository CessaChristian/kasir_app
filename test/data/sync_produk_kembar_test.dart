import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/open_bill/models/isi_bill.dart';

/// Server menggabungkan produk kembar dari dua HP offline
/// (`supabase/produk_kembar.sql`). HP yang kalah harus menerima hasilnya:
/// versinya di server hanya 1 detik lebih baru dari yang tadi ia kirim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;

  const hpA = '00000000-0000-0000-0000-000000000001';
  const hpB = '00000000-0000-0000-0000-000000000002';
  final kirim = DateTime.utc(2026, 11, 4, 10);
  final gabung = kirim.add(const Duration(seconds: 1));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mesin = SyncEngine(db);
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: const Value(hpB),
        name: 'es teh',
        price: 7000,
        updatedAt: Value(kirim),
        syncStatus: const Value('synced'),
      ),
    );
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.into(db.transactionItems).insert(
      TransactionItemsCompanion.insert(
        id: const Value('item-1'),
        transactionId: 'tx-1',
        productId: hpB,
        productName: const Value('es teh'),
        qty: 1,
        priceAtSale: 7000,
        subtotal: 7000,
        updatedAt: Value(kirim),
        syncStatus: const Value('synced'),
      ),
    );
  });
  tearDown(() => db.close());

  Map<String, dynamic> produk(String id, String nama, int harga, {DateTime? hapus}) => {
    'id': id,
    'name': nama,
    'price': harga,
    'category_id': null,
    'has_spicy_option': false,
    'image_path': null,
    'created_at': kirim.toIso8601String(),
    'updated_at': gabung.toIso8601String(),
    'deleted_at': hapus?.toIso8601String(),
    'server_urut': gabung.toIso8601String(),
  };

  test('HP B: tinggal 1 Es Teh, penjualannya pindah, harga jual tetap', () async {
    await mesin.gabungkanTabel('products', [
      produk(hpA, 'Es Teh', 5000),
      produk(hpB, 'es teh', 7000, hapus: gabung),
    ]);
    await mesin.gabungkanTabel('transaction_items', [
      {
        'id': 'item-1',
        'transaction_id': 'tx-1',
        'product_id': hpA,
        'product_name': 'es teh',
        'qty': 1,
        'price_at_sale': 7000,
        'subtotal': 7000,
        'notes': null,
        'created_at': kirim.toIso8601String(),
        'updated_at': gabung.toIso8601String(),
        'deleted_at': null,
        'server_urut': gabung.toIso8601String(),
      },
    ]);

    final aktif = await db.watchProducts().first;
    expect(aktif.map((p) => (p.id, p.price)), [(hpA, 5000)]);

    final item = await (db.select(db.transactionItems)
          ..where((i) => i.id.equals('item-1')))
        .getSingle();
    expect(item.productId, hpA);
    expect(item.priceAtSale, 7000);
    expect(item.productName, 'es teh');
  });

  test('open bill hasil gabungan termuat utuh di HP B', () async {
    await mesin.gabungkanTabel('products', [
      produk(hpA, 'Es Teh', 5000),
      produk(hpB, 'es teh', 7000, hapus: gabung),
    ]);
    final aktif = await db.watchProducts().first;

    // Isi lama menunjuk produk yang sudah terhapus: itulah kenapa server
    // harus memindahkannya.
    final lama = muatIsiBill('[{"p":"$hpB","q":2}]', aktif);
    expect(lama.produkHilang, 1);

    final baru = muatIsiBill('[{"p":"$hpA","q":2}]', aktif);
    expect(baru.produkHilang, 0);
    expect(baru.baris.single.priceAtSale, 5000);
    expect(baru.baris.single.qty, 2);
  });
}
