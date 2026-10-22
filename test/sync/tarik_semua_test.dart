import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `tarikSemua` — dipakai Open Bill sebelum tutup shift dan sesudah bayar/
/// hapus ditolak.
///
/// Bill yang dilunasi HP lain menunjuk transaksi HP itu. Kalau hanya
/// `open_bills` yang ditarik, foreign key lokal menolak bill itu (transaksinya
/// belum ada di sini) dan bill tetap terlihat TERBUKA: kasir tidak bisa
/// menutup shift, dan bill-nya tidak hilang dari Tagihan Nota.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;
  late Map<String, List<Map<String, dynamic>>> server;
  final ditarik = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ditarik.clear();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    await db
        .into(db.shifts)
        .insert(ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
    // Bill masih terbuka di HP ini.
    final lama = DateTime.now().subtract(const Duration(minutes: 5));
    await db
        .into(db.openBills)
        .insert(
          OpenBillsCompanion.insert(
            id: const Value('b-1'),
            name: 'Meja 4',
            shiftId: 's-1',
            userId: 'k-1',
            items: '[]',
            createdAt: Value(lama),
            updatedAt: Value(lama),
            syncStatus: const Value('synced'),
          ),
        );

    final kini = DateTime.now().toUtc().toIso8601String();
    // Server: HP lain sudah melunasi bill itu dengan transaksinya sendiri.
    server = {
      'transactions': [
        {
          'id': 'tx-hp-lain',
          'invoice_no': 'TRX/1',
          'total': 18000,
          'payment_method': 'qris',
          'cash_received': null,
          'change': null,
          'cashier_user_id': 'k-1',
          'shift_id': 's-1',
          'order_type': 'dine_in',
          'bill_name': 'Meja 4',
          'created_at': kini,
          'updated_at': kini,
          'deleted_at': null,
          'cancel_reason': null,
          'cancelled_by_user_id': null,
          'server_urut': kini,
        },
      ],
      'open_bills': [
        {
          'id': 'b-1',
          'name': 'Meja 4',
          'shift_id': 's-1',
          'user_id': 'k-1',
          'items': <Object>[],
          'transaction_id': 'tx-hp-lain',
          'created_at': kini,
          'updated_at': kini,
          'deleted_at': null,
          'server_urut': kini,
        },
      ],
    };
    mesin = SyncEngine(db)
      ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
        ditarik.add(tabel);
        // Halaman kedua dan seterusnya kosong.
        return setelah == null ? (server[tabel] ?? const []) : const [];
      };
  });
  tearDown(() => db.close());

  test(
    'bill lunas HP lain tersimpan lunas: transaksinya ditarik dulu',
    () async {
      await mesin.tarikSemua();
      final bill = await db.select(db.openBills).getSingle();
      expect(bill.transactionId, 'tx-hp-lain');
      expect(
        ditarik.indexOf('transactions'),
        lessThan(ditarik.indexOf('open_bills')),
        reason: 'induk sebelum anak',
      );
    },
  );

  test('menarik open_bills saja gagal karena foreign key (alasan '
      'tarikSemua ada)', () async {
    await expectLater(mesin.tarikTabel('open_bills'), throwsA(anything));
    final bill = await db.select(db.openBills).getSingle();
    expect(bill.transactionId, isNull, reason: 'tetap terlihat terbuka');
  });

  test('tanda "tertutup" sementara tertimpa status asli dari server', () async {
    // Server menjawab "sudah dibayar" → HP menandai bill tertutup lewat
    // deleted_at tanpa mengubah updated_at (OpenBillRepository.tandaiTertutup).
    await (db.update(db.openBills)..where((b) => b.id.equals('b-1'))).write(
      OpenBillsCompanion(deletedAt: Value(DateTime.now())),
    );
    await mesin.tarikSemua();
    final bill = await db.select(db.openBills).getSingle();
    expect(bill.transactionId, 'tx-hp-lain', reason: 'lunas oleh HP lain');
    expect(bill.deletedAt, isNull, reason: 'bukan dihapus');
  });
}
