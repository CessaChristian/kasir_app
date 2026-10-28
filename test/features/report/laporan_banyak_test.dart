import 'dart:ffi';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/report/repositories/laporan_repository.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';

/// Laporan periode panjang. Dulu item struk diambil dengan `isIn(daftar id
/// transaksi)`, dan SQLite menolak lebih dari ±32.766 isian per kueri — jadi
/// periode berisi transaksi sebanyak itu membuat halaman Laporan gagal dimuat.
///
/// SQLite di APK Android dikompilasi dengan `MAX_VARIABLE_NUMBER=32766`
/// (dicek dari libsqlite3.so di APK rilis), sedangkan SQLite di Mac tempat test
/// berjalan 500.000 — makanya bug ini lolos dari test. Batas HP ditiru di sini
/// lewat `sqlite3_limit`.
typedef _LimitC = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _LimitDart = int Function(Pointer<Void>, int, int);
const _sqliteLimitVariableNumber = 9;
const _batasAndroid = 32766;

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;
  setUp(() {
    final limit = DynamicLibrary.process().lookupFunction<_LimitC, _LimitDart>(
      'sqlite3_limit',
    );
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) =>
            limit(raw.handle.cast(), _sqliteLimitVariableNumber, _batasAndroid),
      ),
    );
  });
  tearDown(() => db.close());

  test('40.000 transaksi dalam satu periode tetap bisa dihitung', () async {
    const jumlah = 40000;
    final mulai = DateTime(2026, 1, 1, 10);
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: const Value('p1'),
            name: 'Es Teh',
            price: 5000,
          ),
        );
    await db.batch((b) {
      for (var i = 0; i < jumlah; i++) {
        final waktu = mulai.add(Duration(minutes: i * 10));
        final batal = i == 0;
        b.insert(
          db.transactions,
          TransactionsCompanion.insert(
            id: Value('t$i'),
            total: 5000,
            paymentMethod: 'cash',
            createdAt: Value(waktu),
            deletedAt: Value(batal ? waktu : null),
          ),
        );
        b.insert(
          db.transactionItems,
          TransactionItemsCompanion.insert(
            id: Value('i$i'),
            transactionId: 't$i',
            productId: 'p1',
            productName: const Value('Es Teh'),
            qty: 1,
            priceAtSale: 5000,
            subtotal: 5000,
          ),
        );
      }
    });

    final jam = Stopwatch()..start();
    final r = await LaporanRepository(db).muat(
      Periode(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
      sekarang: DateTime(2026, 12, 31, 23),
    );
    // Kueri yang mencocokkan setiap pasangan baris makan ±70 detik di sini.
    expect(jam.elapsed, lessThan(const Duration(seconds: 10)));
    // Satu transaksi dibatalkan: tidak dihitung, itemnya juga tidak.
    expect(r.jumlahTransaksi, jumlah - 1);
    expect(r.pendapatan, (jumlah - 1) * 5000);
    expect(r.item.values.expand((e) => e).length, jumlah - 1);
    expect(r.item.containsKey('t0'), isFalse);
  });
}
