import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/permission_repository.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/features/report/repositories/laporan_repository.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Izin yang dulu cuma dijaga di tampilan (revisi QA C9): menunya memang
/// disembunyikan dari kasir, tapi fungsi di baliknya tidak memeriksa ulang.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  Future<void> masuk(
    String userId,
    String role, {
    List<String> izin = const [],
    String? shiftId,
  }) => SessionManager.instance.setSession(
    AuthSession.create(
      userId: userId,
      username: userId,
      role: role,
      shiftId: shiftId,
      permissions: izin,
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    for (final (id, role) in [
      ('owner', 'owner'),
      ('sari', 'cashier'),
      ('budi', 'cashier'),
    ]) {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: Value(id),
              username: id,
              pinHash: 'h',
              salt: 's',
              role: role,
            ),
          );
    }
    for (final (id, user) in [('s-sari', 'sari'), ('s-budi', 'budi')]) {
      await db
          .into(db.shifts)
          .insert(ShiftsCompanion.insert(id: Value(id), userId: user));
    }
    await masuk(
      'sari',
      'cashier',
      izin: ['create_transaction', 'open_close_shift'],
      shiftId: 's-sari',
    );
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  final ditolak = throwsA(isA<IzinDitolak>());

  test('kasir tidak bisa mengubah izin siapa pun', () async {
    final repo = PermissionRepository(db);
    await expectLater(
      repo.setUserPermission(
        userId: 'sari',
        permissionCode: 'view_report',
        enabled: true,
      ),
      ditolak,
    );
    await expectLater(
      repo.setUserPermissions(
        userId: 'sari',
        permissions: {'view_report': true},
      ),
      ditolak,
    );
    expect(await db.select(db.userPermissions).get(), isEmpty);
  });

  test('kasir tidak bisa mengganti nama, mencabut, atau melupakan HP', () {
    final repo = PerangkatRepository.untukTest();
    expect(() => repo.ubahNama('hp-1', 'x'), ditolak);
    expect(() => repo.ubahStatus('hp-1', aktif: false), ditolak);
    expect(() => repo.lupakan('hp-1'), ditolak);
  });

  test('kasir tanpa izin Laporan tidak bisa memuatnya', () async {
    final repo = LaporanRepository(db);
    final p = Periode.hari(DateTime(2026, 10, 28));
    await expectLater(repo.muat(p), ditolak);
    expect(() => repo.watchLaporan(p), ditolak);

    await masuk('sari', 'cashier', izin: ['view_report'], shiftId: 's-sari');
    await repo.muat(p, sekarang: DateTime(2026, 10, 28, 12));
  });

  test('Riwayat Shift orang lain butuh izin view_all_shifts', () async {
    final repo = ShiftRepository(db);
    final p = Periode.hari(DateTime(2026, 10, 28));
    expect(() => repo.watchRiwayatShift(p), ditolak);
    expect(() => repo.watchRiwayatShift(p, hanyaUserId: 'budi'), ditolak);
    // Shift sendiri tetap boleh.
    repo.watchRiwayatShift(p, hanyaUserId: 'sari');
  });

  group('pengeluaran', () {
    Future<void> catat({
      required String? shiftId,
      String userId = 'sari',
      int nominal = 5000,
      int qty = 1,
    }) => ExpenseRepository(db).addExpense(
      shiftId: shiftId,
      userId: userId,
      description: 'Es batu',
      amount: nominal,
      qty: qty,
    );

    test('nominal dan jumlah harus wajar', () async {
      await expectLater(
        catat(shiftId: 's-sari', nominal: 0),
        throwsArgumentError,
      );
      await expectLater(
        catat(shiftId: 's-sari', nominal: -100),
        throwsArgumentError,
      );
      await expectLater(catat(shiftId: 's-sari', qty: 0), throwsArgumentError);
    });

    test('kasir hanya di shift miliknya, atas namanya sendiri', () async {
      await expectLater(catat(shiftId: 's-budi'), ditolak);
      await expectLater(catat(shiftId: 's-sari', userId: 'budi'), ditolak);
      await catat(shiftId: 's-sari');
      expect(await db.select(db.expenses).get(), hasLength(1));
    });

    test('owner bebas, termasuk tanpa shift', () async {
      await masuk('owner', 'owner');
      await catat(shiftId: null, userId: 'owner');
      await catat(shiftId: 's-budi', userId: 'owner');
    });
  });

  test('aksi akun kasir hanya untuk akun KASIR yang masih ada', () async {
    await masuk('owner', 'owner');
    final repo = CashierRepository(
      db,
      namaDipakaiDiServer: (_, _) async => false,
      terhubung: () async => true,
    );
    final tidakAda = throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'pesan',
        'Akun kasir tidak ditemukan.',
      ),
    );
    await expectLater(repo.toggleCashierStatus('owner', false), tidakAda);
    await expectLater(repo.resetCashierPin('owner', '123456'), tidakAda);
    await expectLater(repo.toggleCashierStatus('hantu', false), tidakAda);
    await repo.hapusKasir('budi');
    await expectLater(repo.resetCashierPin('budi', '123456'), tidakAda);
  });
}
