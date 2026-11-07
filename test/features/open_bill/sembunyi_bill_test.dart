import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 6 Nov nomor 25: menyembunyikan bill "sudah dibayar HP lain" memakai
/// `deleted_at`. Bill yang masih menunggu dikirim membawa tanda itu ke server
/// dan terhapus di semua HP, walau sebenarnya masih terbuka.
void main() {
  late AppDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value('k-1'), username: 'sari', pinHash: 'h', salt: 's',
        role: 'cashier'));
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
  });
  tearDown(() => db.close());

  Future<OpenBill> bill(String status) async {
    await db.into(db.openBills).insert(OpenBillsCompanion.insert(
          id: Value('b-$status'),
          name: 'Meja $status',
          shiftId: 's-1',
          userId: 'k-1',
          items: '[]',
          syncStatus: Value(status),
        ));
    await OpenBillRepository(db).tandaiTertutup('b-$status');
    return (db.select(db.openBills)..where((b) => b.id.equals('b-$status')))
        .getSingle();
  }

  test('bill yang sudah terkirim langsung disembunyikan', () async {
    expect((await bill('synced')).deletedAt, isNotNull);
  });

  test('bill yang belum terkirim TIDAK disembunyikan lewat deleted_at',
      () async {
    final b = await bill('pending');
    expect(b.deletedAt, isNull, reason: 'akan ikut terkirim sebagai hapus');
  });
}
