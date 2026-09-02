import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menguji ExpenseRepository benar-benar meneruskan parameter ke database.
///
/// Repository memang lapisan tipis, tapi justru di situ salah pasang parameter
/// gampang lolos: `shiftId` dan `userId` sama-sama String, jadi tertukar pun
/// tetap lolos analyzer. Sudah dibuktikan test ini menangkapnya.
///
/// Jalur tulis pengeluaran juga tidak bisa diuji lewat akun owner di emulator
/// karena owner tidak punya shift, sementara `expenses.shift_id` wajib diisi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db);

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'sari',
          pinHash: 'hash',
          salt: 'salt',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'kasir-1',
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'kasir-1',
      username: 'sari',
      role: 'owner', // owner = punya semua permission
      shiftId: 'shift-1',
      permissions: const [],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<Expense> addOne({
    String description = 'Beli gas',
    int amount = 25000,
  }) async {
    await repo.addExpense(
      shiftId: 'shift-1',
      userId: 'kasir-1',
      description: description,
      amount: amount,
    );
    return db.select(db.expenses).getSingle();
  }

  test('addExpense menyimpan nilai persis seperti yang dikirim', () async {
    final e = await addOne(description: 'Beli gas', amount: 25000);

    expect(e.description, 'Beli gas');
    expect(e.amount, 25000);
    expect(e.shiftId, 'shift-1');
    expect(e.userId, 'kasir-1');
    expect(e.deletedAt, isNull);
  });

  test('updateExpense mengubah nominal dan keterangan', () async {
    final e = await addOne();

    await repo.updateExpense(
      id: e.id,
      amount: 40000,
      description: 'Beli gas + galon',
    );

    final after = await db.select(db.expenses).getSingle();
    expect(after.amount, 40000);
    expect(after.description, 'Beli gas + galon');
    expect(after.syncStatus, 'pending', reason: 'perlu dikirim ke server');
  });

  test('deleteExpense menandai terhapus, barisnya tetap ada', () async {
    final e = await addOne();

    await repo.deleteExpense(e.id);

    final row = await db.select(db.expenses).getSingle();
    expect(row.deletedAt, isNotNull, reason: 'ditandai, bukan dibuang');
    expect(row.syncStatus, 'pending');

    expect(await repo.watchExpensesByShift('shift-1').first, isEmpty,
        reason: 'tidak muncul lagi di daftar shift');
    expect(await repo.getExpensesByShift('shift-1'), isEmpty);
  });

  test('watchExpensesByShift dan getExpensesByShift sepakat isinya', () async {
    await addOne(description: 'Beli gas', amount: 25000);
    await repo.addExpense(
      shiftId: 'shift-1',
      userId: 'kasir-1',
      description: 'Parkir',
      amount: 5000,
    );

    final stream = await repo.watchExpensesByShift('shift-1').first;
    final once = await repo.getExpensesByShift('shift-1');

    expect(stream, hasLength(2));
    expect(once.map((e) => e.id).toSet(), stream.map((e) => e.id).toSet());
    expect(once.map((e) => e.amount).reduce((a, b) => a + b), 30000);
  });

  test('getAllExpensesForOwner membawa nama pencatatnya', () async {
    await addOne(description: 'Beli gas', amount: 25000);

    final entries = await repo.getAllExpensesForOwner();

    expect(entries, hasLength(1));
    expect(entries.single.username, 'sari');
    expect(entries.single.expense.amount, 25000);
  });
}
