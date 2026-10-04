import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/dashboard/repositories/dasbor_owner_repository.dart';
import 'package:kasir_app/utils/currency_formatter.dart';

/// Kartu "Ringkasan hari ini" di dashboard owner.
void main() {
  late AppDatabase db;
  late DasborOwnerRepository repo;

  // Sabtu 3 Okt 2026, 14.00.
  final sekarang = DateTime(2026, 10, 3, 14, 0);

  Future<void> trx(String id, DateTime waktu, int total,
      {String metode = 'cash', String shift = 's-budi', bool batal = false}) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: Value(id),
            cashierUserId: const Value('budi'),
            shiftId: Value(shift),
            createdAt: Value(waktu),
            total: total,
            paymentMethod: metode,
            deletedAt: Value(batal ? waktu : null),
          ));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DasborOwnerRepository(db);
    for (final (id, nama) in [('budi', 'budi'), ('sari', 'sari')]) {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: nama,
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ));
    }
  });

  tearDown(() => db.close());

  group('persenPerubahan', () {
    test('naik, turun, dibulatkan', () {
      expect(persenPerubahan(150, 100), 50);
      expect(persenPerubahan(50, 100), -50);
      expect(persenPerubahan(101, 300), -66);
    });

    test('kemarin nol → null, bukan pembagian dengan nol', () {
      expect(persenPerubahan(5000, 0), isNull);
      expect(persenPerubahan(0, 0), isNull);
    });
  });

  test('formatRp menangani angka negatif (laba kotor bisa minus)', () {
    expect(formatRp(1250000), 'Rp 1.250.000');
    expect(formatRp(0), 'Rp 0');
    expect(formatRp(-100), '-Rp 100');
    expect(formatRp(-25000), '-Rp 25.000');
  });

  test('pendapatan hari ini: transaksi batal dan transaksi kemarin tidak ikut',
      () async {
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: const Value('s-budi'),
        userId: 'budi',
        startAt: Value(DateTime(2026, 10, 3, 8))));
    await trx('t1', DateTime(2026, 10, 3, 9), 20000);
    await trx('t2', DateTime(2026, 10, 3, 10), 30000, metode: 'qris');
    await trx('t3', DateTime(2026, 10, 3, 11), 99000, batal: true);
    await trx('t4', DateTime(2026, 10, 2, 9), 70000);
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          shiftId: const Value('s-budi'),
          userId: 'budi',
          description: 'Es batu',
          amount: 60000,
          createdAt: Value(DateTime(2026, 10, 3, 9, 30)),
        ));

    final r = await repo.muat(sekarang: sekarang);
    expect(r.pendapatan, 50000);
    expect(r.transaksi, 2);
    expect(r.tunai, 1);
    expect(r.qris, 1);
    expect(r.pengeluaran, 60000);
    expect(r.labaKotor, -10000);
  });

  test('pembanding kemarin hanya sampai jam yang sama dengan sekarang',
      () async {
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-budi'), userId: 'budi'));
    await trx('k1', DateTime(2026, 10, 2, 9), 40000);
    await trx('k2', DateTime(2026, 10, 2, 13, 59), 10000);
    // Lewat jam sekarang — belum terjadi "di jam yang sama".
    await trx('k3', DateTime(2026, 10, 2, 14, 1), 500000);
    await trx('k4', DateTime(2026, 10, 2, 10), 80000, batal: true);
    await trx('h1', DateTime(2026, 10, 3, 9), 75000);

    final r = await repo.muat(sekarang: sekarang);
    expect(r.pendapatanKemarin, 50000);
    expect(r.persenVsKemarin, 50);
  });

  test('shift berjalan beserta nama, jumlah, dan pendapatannya', () async {
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: const Value('s-budi'),
        userId: 'budi',
        startAt: Value(DateTime(2026, 10, 3, 8))));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: const Value('s-lama'),
        userId: 'sari',
        startAt: Value(DateTime(2026, 10, 3, 6)),
        endAt: Value(DateTime(2026, 10, 3, 7, 45))));
    await trx('t1', DateTime(2026, 10, 3, 9), 20000);
    await trx('t2', DateTime(2026, 10, 3, 9, 5), 15000, batal: true);

    final r = await repo.muat(sekarang: sekarang);
    expect(r.shiftBerjalan, hasLength(1));
    final s = r.shiftBerjalan.single;
    expect(s.namaKasir, 'budi');
    expect(s.mulai, DateTime(2026, 10, 3, 8));
    expect(s.transaksi, 1);
    expect(s.pendapatan, 20000);
    expect(r.shiftTerakhirDitutup, DateTime(2026, 10, 3, 7, 45));
  });

  test('shift yang ditutup kemarin tidak disebut "terakhir ditutup"',
      () async {
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: const Value('s-kemarin'),
        userId: 'sari',
        startAt: Value(DateTime(2026, 10, 2, 16)),
        endAt: Value(DateTime(2026, 10, 2, 22))));

    final r = await repo.muat(sekarang: sekarang);
    expect(r.shiftBerjalan, isEmpty);
    expect(r.shiftTerakhirDitutup, isNull);
  });
}
