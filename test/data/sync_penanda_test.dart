import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci aturan: SETIAP perubahan data harus menandai barisnya
/// `sync_status = 'pending'` DAN memperbarui `updated_at`.
///
/// Latar belakang — penjualan mengurangi stok lewat SQL mentah yang hanya
/// menyentuh kolom `stock`:
///
/// ```sql
/// UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?
/// ```
///
/// Akibatnya baris tetap bertanda 'synced' dengan `updated_at` lama, jadi
/// mesin sync menganggapnya tidak pernah berubah. Stok berkurang di HP kasir
/// tapi TIDAK PERNAH sampai ke server — owner melihat angka basi selamanya,
/// padahal memantau stok justru alasan utama adanya sync.
///
/// Gagalnya diam-diam: tidak ada error, transaksinya sukses, stoknya benar
/// secara lokal. Hanya perbandingan dengan server yang bisa mengungkapnya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'sari',
          pinHash: 'hash',
          salt: 'salt',
          role: 'cashier',
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'kasir-1',
      username: 'sari',
      role: 'cashier',
      shiftId: null,
      permissions: const ['create_transaction', 'delete_own_transaction'],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<Product> produkDenganStok(int stok) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Mie Goreng',
          price: 16000,
          trackStock: const Value(true),
          stock: Value(stok),
        ));
    // Anggap sudah pernah tersinkron sejam lalu, seperti produk yang ditarik
    // dari server. Waktunya sengaja dimundurkan: drift menyimpan waktu dalam
    // resolusi DETIK, jadi kalau produk dibuat dan langsung dijual dalam
    // detik yang sama, `updated_at` tidak akan terlihat maju.
    await (db.update(db.products)..where((p) => p.id.equals('prod-1'))).write(
      ProductsCompanion(
        syncStatus: const Value('synced'),
        updatedAt: Value(DateTime.now().subtract(const Duration(hours: 1))),
      ),
    );
    return (db.select(db.products)..where((p) => p.id.equals('prod-1')))
        .getSingle();
  }

  test('penjualan menandai produk perlu dikirim ulang', () async {
    final sebelum = await produkDenganStok(180);
    expect(sebelum.syncStatus, 'synced', reason: 'kondisi awal');

    await db.createSale(
      transactionId: 'e1b7c4a2-0000-4000-8000-000000000001',
      paymentMethod: 'cash',
      cashReceived: 50000,
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Mie Goreng',
          qty: 2,
          priceAtSale: 16000,
          trackStock: true,
        ),
      ],
    );

    final sesudah = await (db.select(db.products)
          ..where((p) => p.id.equals('prod-1')))
        .getSingle();

    expect(sesudah.stock, 178, reason: 'stok berkurang');
    expect(sesudah.syncStatus, 'pending',
        reason: 'stok berubah → WAJIB dikirim ke server. Kalau tetap '
            "'synced', perubahan stok tidak akan pernah sampai ke owner.");
    expect(sesudah.updatedAt.isAfter(sebelum.updatedAt), isTrue,
        reason: 'updated_at harus maju — mesin sync memakainya untuk '
            'menentukan baris mana yang berubah');
  });

  test('pembatalan transaksi juga menandai produk perlu dikirim', () async {
    await produkDenganStok(180);
    await db.createSale(
      transactionId: 'e1b7c4a2-0000-4000-8000-000000000002',
      paymentMethod: 'cash',
      cashReceived: 50000,
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Mie Goreng',
          qty: 2,
          priceAtSale: 16000,
          trackStock: true,
        ),
      ],
    );
    // Kembalikan ke 'synced' supaya perubahan berikutnya benar-benar teruji.
    await (db.update(db.products)..where((p) => p.id.equals('prod-1')))
        .write(const ProductsCompanion(syncStatus: Value('synced')));

    await db.softDeleteTransaction('e1b7c4a2-0000-4000-8000-000000000002');

    final p = await (db.select(db.products)
          ..where((t) => t.id.equals('prod-1')))
        .getSingle();
    expect(p.stock, 180, reason: 'stok dikembalikan');
    expect(p.syncStatus, 'pending', reason: 'pengembalian stok juga harus dikirim');
  });

  test('transaksi dan itemnya lahir dengan status menunggu kirim', () async {
    await produkDenganStok(180);
    await db.createSale(
      transactionId: 'e1b7c4a2-0000-4000-8000-000000000003',
      paymentMethod: 'cash',
      cashReceived: 50000,
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Mie Goreng',
          qty: 1,
          priceAtSale: 16000,
          trackStock: true,
        ),
      ],
    );

    final tx = await db.select(db.transactions).getSingle();
    final item = await db.select(db.transactionItems).getSingle();
    expect(tx.syncStatus, 'pending');
    expect(item.syncStatus, 'pending',
        reason: 'transaksi yang dibuat saat offline harus antre terkirim');
  });
}
