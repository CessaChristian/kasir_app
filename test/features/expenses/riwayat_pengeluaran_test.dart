import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/expenses/expenses_page.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';

/// Mengunci dua aturan halaman Pengeluaran yang dulu dilanggar diam-diam.
///
/// 1. RIWAYAT HANYA BERISI SHIFT YANG PUNYA PENGELUARAN.
///    Dulu tiap kartu memuat pengeluarannya sendiri, dan baru saat dibuka.
///    Akibatnya halaman tidak pernah tahu kartu mana yang kosong, jadi shift
///    tanpa satu pun catatan tetap terdaftar dan harus dibuka satu per satu
///    untuk ketahuan kosong.
///
/// 2. OWNER MELIHAT SHIFT SEMUA AKUN, KASIR HANYA MILIKNYA.
///    Dulu keduanya memakai `getShiftsByUser(session.userId)`, sehingga owner
///    — yang tidak menjalankan shift — malah melihat sisa shift lamanya
///    sendiri, bukan shift kasir yang seharusnya ia awasi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpenseRepository expenseRepo;
  late ShiftRepository shiftRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenseRepo = ExpenseRepository(db);
    shiftRepo = ShiftRepository(db);

    for (final (id, nama, peran) in [
      ('owner-1', 'cessa', 'owner'),
      ('kasir-1', 'sari', 'cashier'),
      ('kasir-2', 'budi', 'cashier'),
    ]) {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: nama,
            pinHash: 'hash',
            salt: 'salt',
            role: peran,
          ));
    }

    // shift-a: milik sari, ADA pengeluaran
    // shift-b: milik sari, KOSONG
    // shift-c: milik budi, ADA pengeluaran
    // shift-d: milik owner (sisa lama), KOSONG
    for (final (id, userId) in [
      ('shift-a', 'kasir-1'),
      ('shift-b', 'kasir-1'),
      ('shift-c', 'kasir-2'),
      ('shift-d', 'owner-1'),
    ]) {
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: Value(id),
            userId: userId,
          ));
    }

    await expenseRepo.addExpense(
      shiftId: 'shift-a',
      userId: 'kasir-1',
      description: 'Beli gas',
      amount: 25000,
    );
    await expenseRepo.addExpense(
      shiftId: 'shift-a',
      userId: 'kasir-1',
      description: 'Beli galon',
      amount: 6000,
    );
    await expenseRepo.addExpense(
      shiftId: 'shift-c',
      userId: 'kasir-2',
      description: 'Parkir',
      amount: 3000,
    );
  });

  tearDown(() async => db.close());

  test('shift tanpa pengeluaran tidak muncul sebagai kunci', () async {
    final hasil = await expenseRepo.getExpensesForShifts(
      ['shift-a', 'shift-b', 'shift-c', 'shift-d'],
    );

    // Inilah penyaringnya: halaman membuang shift yang tidak jadi kunci.
    expect(hasil.keys.toSet(), {'shift-a', 'shift-c'});
    expect(hasil['shift-b'], isNull, reason: 'shift kosong tidak boleh ikut');
    expect(hasil['shift-d'], isNull, reason: 'shift kosong tidak boleh ikut');
  });

  test('pengeluaran dikelompokkan ke shift yang benar', () async {
    final hasil = await expenseRepo.getExpensesForShifts(['shift-a', 'shift-c']);

    expect(hasil['shift-a']!.map((e) => e.description),
        ['Beli gas', 'Beli galon']);
    expect(hasil['shift-c']!.map((e) => e.description), ['Parkir']);
    expect(hasil['shift-a']!.fold<int>(0, (s, e) => s + e.amount), 31000);
  });

  test('pengeluaran terhapus tidak ikut, dan shift bisa jadi kosong karenanya',
      () async {
    final parkir =
        (await expenseRepo.getExpensesForShifts(['shift-c']))['shift-c']!.single;
    await expenseRepo.deleteExpense(parkir.id);

    final hasil = await expenseRepo.getExpensesForShifts(['shift-a', 'shift-c']);
    expect(hasil.containsKey('shift-c'), isFalse);
    expect(hasil.containsKey('shift-a'), isTrue);
  });

  test('daftar shift kosong tidak memukul database', () async {
    expect(await expenseRepo.getExpensesForShifts([]), isEmpty);
  });

  test('owner mendapat shift SEMUA akun, beserta nama kasirnya', () async {
    final hasil = await shiftRepo.getShiftsWithUser();

    expect(hasil.map((e) => e.shift.id).toSet(),
        {'shift-a', 'shift-b', 'shift-c', 'shift-d'});
    expect(
      {for (final e in hasil) e.shift.id: e.username},
      {
        'shift-a': 'sari',
        'shift-b': 'sari',
        'shift-c': 'budi',
        'shift-d': 'cessa',
      },
    );
  });

  test('kasir hanya mendapat shift miliknya sendiri', () async {
    final hasil = await shiftRepo.getShiftsWithUser(userId: 'kasir-1');

    expect(hasil.map((e) => e.shift.id).toSet(), {'shift-a', 'shift-b'});
    expect(hasil.every((e) => e.username == 'sari'), isTrue);
  });

  test('shift terhapus tidak ikut terambil', () async {
    await (db.update(db.shifts)..where((s) => s.id.equals('shift-c')))
        .write(ShiftsCompanion(deletedAt: Value(DateTime.now())));

    final hasil = await shiftRepo.getShiftsWithUser();
    expect(hasil.map((e) => e.shift.id).contains('shift-c'), isFalse);
  });

  group('riwayatLayakTampil', () {
    ShiftEntry entri(String id, {DateTime? selesai}) => ShiftEntry(
          shift: Shift(
            id: id,
            userId: 'kasir-1',
            startAt: DateTime(2026, 9, 25, 8),
            endAt: selesai,
            syncStatus: 'pending',
            updatedAt: DateTime(2026, 9, 25, 8),
          ),
          username: 'sari',
        );

    Expense catatan(String shiftId) => Expense(
          id: 'e-$shiftId',
          shiftId: shiftId,
          userId: 'kasir-1',
          description: 'Beli gas',
          amount: 1000,
          createdAt: DateTime(2026, 9, 25, 9),
          syncStatus: 'pending',
          updatedAt: DateTime(2026, 9, 25, 9),
        );

    test('shift yang MASIH BERJALAN tetap tampil — titik buta owner', () {
      // Dulu syaratnya `endAt != null`, jadi pemilik tidak bisa melihat
      // pengeluaran kasir yang sedang bertugas sampai shiftnya ditutup.
      final hasil = riwayatLayakTampil(
        semua: [entri('berjalan')],
        perShift: {
          'berjalan': [catatan('berjalan')]
        },
        shiftAktifSaya: null,
      );

      expect(hasil.map((e) => e.shift.id), ['berjalan']);
      expect(hasil.single.shift.endAt, isNull);
    });

    test('shift aktif MILIK SENDIRI tidak tampil — sudah ada di atasnya', () {
      final hasil = riwayatLayakTampil(
        semua: [entri('punyaku'), entri('lain', selesai: DateTime(2026, 9, 25, 16))],
        perShift: {
          'punyaku': [catatan('punyaku')],
          'lain': [catatan('lain')],
        },
        shiftAktifSaya: 'punyaku',
      );

      expect(hasil.map((e) => e.shift.id), ['lain']);
    });

    test('shift tanpa pengeluaran tidak tampil', () {
      final hasil = riwayatLayakTampil(
        semua: [entri('isi', selesai: DateTime(2026, 9, 25, 16)), entri('kosong', selesai: DateTime(2026, 9, 25, 17))],
        perShift: {
          'isi': [catatan('isi')]
        },
        shiftAktifSaya: null,
      );

      expect(hasil.map((e) => e.shift.id), ['isi']);
    });

    test('urutan dari kueri dipertahankan', () {
      final hasil = riwayatLayakTampil(
        semua: [entri('a'), entri('b'), entri('c')],
        perShift: {
          'a': [catatan('a')],
          'b': [catatan('b')],
          'c': [catatan('c')],
        },
        shiftAktifSaya: null,
      );

      expect(hasil.map((e) => e.shift.id), ['a', 'b', 'c']);
    });
  });
}
