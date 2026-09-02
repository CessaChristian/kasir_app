import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci CHECK constraint pada kolom yang berperan sebagai enum.
///
/// SQLite tidak punya tipe ENUM, jadi kolom TEXT menerima salah ketik apa pun.
/// Ini sudah terbukti merugikan: `transactions.order_type` sempat berisi 163
/// baris `'takeaway'` (tanpa garis bawah) sementara kode memakai `'take_away'`,
/// dan seluruhnya terhitung sebagai Dine In di laporan tanpa error apa pun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<String> ddl(String table) async {
    final rows = await db
        .customSelect("SELECT sql FROM sqlite_master WHERE name = ?",
            variables: [Variable<String>(table)])
        .getSingle();
    return rows.data['sql'] as String;
  }

  test('CHECK benar-benar terpasang di DDL', () async {
    expect(await ddl('transactions'),
        contains("CHECK (order_type IN ('dine_in', 'take_away', 'delivery'))"));
    expect(await ddl('transactions'),
        contains("CHECK (payment_method IN ('cash', 'qris'))"));
    expect(await ddl('users'), contains("CHECK (role IN ('owner', 'cashier'))"));
  });

  test('order_type salah ketik DITOLAK database', () async {
    // Persis bug yang pernah terjadi: 'takeaway' tanpa garis bawah.
    await expectLater(
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            total: 15000,
            paymentMethod: 'cash',
            orderType: const Value('takeaway'),
          )),
      throwsA(anything),
      reason: 'nilai enum di luar daftar harus ditolak',
    );

    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('order_type yang sah tetap diterima', () async {
    for (final v in ['dine_in', 'take_away', 'delivery']) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            total: 1000,
            paymentMethod: 'qris',
            orderType: Value(v),
          ));
    }
    expect(await db.select(db.transactions).get(), hasLength(3));
  });

  test('payment_method dan role juga dijaga', () async {
    await expectLater(
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            total: 1000,
            paymentMethod: 'gopay', // belum didukung
          )),
      throwsA(anything),
    );

    await expectLater(
      db.into(db.users).insert(UsersCompanion.insert(
            username: 'budi',
            pinHash: 'hash',
            salt: 'salt',
            role: 'admin', // hanya owner/cashier yang sah
          )),
      throwsA(anything),
    );
  });
}
