import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aturan simpan produk di database — jaring kedua di belakang formulir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'o-1',
        username: 'owner',
        role: 'owner',
        shiftId: null,
        permissions: const [],
      ),
    );
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> simpan(String id, String nama, {int harga = 5000}) =>
      db.upsertProduct(
        id: id,
        name: nama,
        price: harga,
        hasSpicyOption: false,
        hasSweetOption: false,
        hasIceOption: false,
      );

  test('nama kembar ditolak, tidak peduli besar-kecil huruf & spasi', () async {
    await simpan('p1', 'Es Teh');
    expect(
      () => simpan('p2', '  es teh '),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'pesan',
          'Produk bernama "es teh" sudah ada.',
        ),
      ),
    );
  });

  test('menyimpan ulang produk yang sama bukan "kembar"', () async {
    await simpan('p1', 'Es Teh');
    await simpan('p1', 'Es Teh', harga: 6000);
    final p = await (db.select(db.products)).getSingle();
    expect(p.price, 6000);
  });

  test('nama produk yang sudah dihapus boleh dipakai lagi', () async {
    await simpan('p1', 'Es Teh');
    await db.deleteProduct('p1');
    await simpan('p2', 'Es Teh');
  });

  test(
    'edit produk yang sudah dihapus HP lain: ditolak dengan pesan',
    () async {
      await simpan('p1', 'Es Teh');
      await db.deleteProduct('p1');
      expect(
        () => simpan('p1', 'Es Teh Manis'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'pesan',
            'Produk ini sudah dihapus di perangkat lain.',
          ),
        ),
      );
    },
  );

  test('nama kosong, terlalu panjang, dan harga tidak wajar ditolak', () async {
    expect(() => simpan('p1', '   '), throwsArgumentError);
    expect(() => simpan('p1', 'x' * 41), throwsArgumentError);
    expect(() => simpan('p1', 'Kopi', harga: 0), throwsArgumentError);
    expect(() => simpan('p1', 'Kopi', harga: 1000000000), throwsArgumentError);
    await simpan('p1', 'x' * 40, harga: 999999999);
  });

  test('nama disimpan tanpa spasi di ujung', () async {
    await simpan('p1', '  Kopi Susu  ');
    expect((await db.select(db.products).getSingle()).name, 'Kopi Susu');
  });
}
