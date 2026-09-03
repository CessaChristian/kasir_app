import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci aturan: setiap baris yang lahir atau berubah WAJIB bertanda
/// `sync_status = 'pending'`, karena kolom itulah antrean pengiriman.
///
/// Latar belakang — pernah ada perubahan data yang lolos tanpa ditandai:
/// SQL mentah yang menyentuh satu kolom saja, sehingga barisnya tetap
/// 'synced' dan mesin sync menganggapnya tidak pernah berubah.
///
/// Kegagalannya DIAM-DIAM: tidak ada error, data benar secara lokal, dan
/// hanya perbandingan dengan server yang bisa mengungkapnya.
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
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Mie Goreng',
          price: 16000,
        ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> jual(String trxId) => db.createSale(
        transactionId: trxId,
        paymentMethod: 'cash',
        cashReceived: 50000,
        orderType: 'dine_in',
        lines: [
          SaleLine(
            productId: 'prod-1',
            productName: 'Mie Goreng',
            qty: 2,
            priceAtSale: 16000,
          ),
        ],
      );

  test('transaksi dan itemnya lahir dengan status menunggu kirim', () async {
    await jual('e1b7c4a2-0000-4000-8000-000000000001');

    final tx = await db.select(db.transactions).getSingle();
    final item = await db.select(db.transactionItems).getSingle();
    expect(tx.syncStatus, 'pending',
        reason: 'transaksi yang dibuat saat offline harus antre terkirim');
    expect(item.syncStatus, 'pending');
  });

  test('pembatalan transaksi ikut ditandai perlu dikirim', () async {
    const id = 'e1b7c4a2-0000-4000-8000-000000000002';
    await jual(id);

    // Anggap sudah sempat terkirim, supaya perubahan berikutnya benar-benar
    // teruji dan bukan sekadar mewarisi status 'pending' dari pembuatan.
    await db.customUpdate("UPDATE transactions SET sync_status='synced'");
    await db.customUpdate("UPDATE transaction_items SET sync_status='synced'");

    await db.softDeleteTransaction(id);

    final tx = await db.select(db.transactions).getSingle();
    final item = await db.select(db.transactionItems).getSingle();
    expect(tx.deletedAt, isNotNull, reason: 'ditandai terhapus');
    expect(tx.syncStatus, 'pending',
        reason: 'penghapusan HARUS sampai ke server. Penghapusan lunak bisa '
            'dikirim justru karena barisnya tetap ada — baris yang '
            'benar-benar lenyap tidak bisa diberitahukan ke perangkat lain.');
    expect(item.syncStatus, 'pending');
  });

  test('mengubah produk menandainya perlu dikirim', () async {
    await db.customUpdate("UPDATE products SET sync_status='synced'");

    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'kasir-1',
      username: 'sari',
      role: 'owner',
      shiftId: null,
      permissions: const ['manage_products'],
    ));
    await db.upsertProduct(
      id: 'prod-1',
      name: 'Mie Goreng Spesial',
      price: 18000,
      hasSpicyOption: false,
    );

    final p = await db.select(db.products).getSingle();
    expect(p.name, 'Mie Goreng Spesial');
    expect(p.syncStatus, 'pending',
        reason: 'perubahan produk oleh pemilik harus sampai ke perangkat lain');
  });
}
