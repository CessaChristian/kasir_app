import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';

/// Ganti nama kasir — satu akun = satu orang.
///
/// Akun tidak pernah dihapus. Ganti nama dipakai untuk membetulkan salah
/// ketik, jadi riwayat lama WAJIB ikut memakai nama baru: shift, transaksi,
/// dan pengeluaran menunjuk akun lewat id, dan laporan membaca namanya saat
/// ditampilkan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<(String, String)> ditanyakanKeServer;
  var namaDiServer = <String>{};
  Object? galatServer;

  CashierRepository repo() => CashierRepository(
        db,
        namaDipakaiDiServer: (nama, kecualiId) async {
          ditanyakanKeServer.add((nama, kecualiId));
          if (galatServer != null) throw galatServer!;
          return namaDiServer.contains(nama);
        },
      );

  Future<void> masukSebagai(String id, String role) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: id,
        username: id,
        role: role,
        shiftId: null,
        permissions: role == 'owner' ? const ['manage_cashiers'] : const [],
      ));

  Future<void> pasangUser(String id, String nama, String role) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: nama,
            pinHash: 'h',
            salt: 's',
            role: role,
            syncStatus: const Value('synced'),
          ));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    ditanyakanKeServer = [];
    namaDiServer = {};
    galatServer = null;

    await pasangUser('owner', 'owner', 'owner');
    await pasangUser('k-1', 'bdui', 'cashier');
    await pasangUser('k-2', 'sari', 'cashier');
    await masukSebagai('owner', 'owner');
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test('salah ketik dibetulkan, dan RIWAYAT LAMA ikut memakai nama baru',
      () async {
    final mulai = DateTime(2026, 10, 1, 8);
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('s-1'),
          userId: 'k-1',
          startAt: Value(mulai),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('t-1'),
          shiftId: const Value('s-1'),
          cashierUserId: const Value('k-1'),
          total: 15000,
          paymentMethod: 'cash',
          createdAt: Value(mulai.add(const Duration(hours: 1))),
        ));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: const Value('e-1'),
          shiftId: const Value('s-1'),
          userId: 'k-1',
          description: 'Es batu',
          amount: 5000,
          createdAt: Value(mulai.add(const Duration(hours: 2))),
        ));

    await repo().gantiNamaKasir('k-1', '  budi  ');

    final akun = await (db.select(db.users)..where((u) => u.id.equals('k-1')))
        .getSingle();
    expect(akun.username, 'budi', reason: 'spasi di ujung dibuang');
    expect(akun.syncStatus, 'pending',
        reason: 'tanpa ini nama barunya tidak pernah sampai ke HP lain');

    final shift = await db.getShiftsWithUser();
    expect(shift.single.username, 'budi');

    final riwayatShift = await ShiftRepository(db).watchShift('s-1').first;
    expect(riwayatShift!.namaKasir, 'budi');
  });

  test('nama yang sudah dipakai akun lain DI HP INI ditolak', () async {
    await expectLater(repo().gantiNamaKasir('k-1', 'sari'),
        throwsA(isA<StateError>()));
    final akun = await (db.select(db.users)..where((u) => u.id.equals('k-1')))
        .getSingle();
    expect(akun.username, 'bdui');
  });

  test('nama yang sudah dipakai di SERVER ditolak walau belum ada di HP ini',
      () async {
    // HP lain baru membuat akun "budi" yang belum tertarik ke sini.
    namaDiServer = {'budi'};

    await expectLater(repo().gantiNamaKasir('k-1', 'budi'),
        throwsA(isA<StateError>()));
    expect(ditanyakanKeServer, [('budi', 'k-1')],
        reason: 'akun itu sendiri dikecualikan dari pemeriksaan');
  });

  test('server tidak bisa dihubungi: nama TIDAK diganti', () async {
    galatServer = StateError('Ganti nama butuh internet');

    await expectLater(repo().gantiNamaKasir('k-1', 'budi'),
        throwsA(isA<StateError>()));
    final akun = await (db.select(db.users)..where((u) => u.id.equals('k-1')))
        .getSingle();
    expect(akun.username, 'bdui');
  });

  test('nama terlalu pendek atau panjang ditolak', () async {
    await expectLater(
        repo().gantiNamaKasir('k-1', 'ab'), throwsA(isA<ArgumentError>()));
    await expectLater(repo().gantiNamaKasir('k-1', 'a' * 31),
        throwsA(isA<ArgumentError>()));
  });

  test('akun owner tidak bisa diganti lewat sini', () async {
    await expectLater(repo().gantiNamaKasir('owner', 'bos'),
        throwsA(isA<StateError>()));
  });

  test('kasir tanpa izin kelola kasir tidak bisa mengganti nama', () async {
    await masukSebagai('k-2', 'cashier');
    await expectLater(repo().gantiNamaKasir('k-1', 'budi'),
        throwsA(isA<StateError>()));
    expect(ditanyakanKeServer, isEmpty);
  });

  test('kasir yang sedang login ikut melihat nama barunya sesudah sinkron',
      () async {
    await masukSebagai('k-1', 'cashier');
    // Nama baru tiba lewat sinkron dari HP owner.
    await (db.update(db.users)..where((u) => u.id.equals('k-1')))
        .write(const UsersCompanion(username: Value('budi')));

    final awal = SessionManager.instance.sesiBerubah.value;
    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.currentSession?.username, 'budi');
    expect(SessionManager.instance.sesiBerubah.value, greaterThan(awal),
        reason: 'menu & dashboard hanya menggambar ulang kalau diberi tahu');
  });
}
