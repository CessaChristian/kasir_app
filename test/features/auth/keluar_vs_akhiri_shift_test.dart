import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Keluar" dan "Akhiri Shift" adalah dua perbuatan yang BERBEDA.
///
/// ── MASALAH YANG DIKUNCI ──
///
/// Dulu keduanya memanggil `logout()` yang sama, dan `logout()` selalu
/// mengisi `endAt`. Jadi walaupun tombolnya dua dan namanya berbeda,
/// akibatnya identik: shiftnya tutup.
///
/// Itu baru terasa sejak satu shift bisa dipegang lebih dari satu HP. Kasir
/// yang cuma meminjam HP rekan lalu menekan "Keluar" ikut menutup shift yang
/// masih berjalan di HP-nya sendiri — dan HP itu tetap bisa berjualan ke
/// shift yang sudah tutup, sehingga rekapnya memuat penjualan yang terjadi
/// SESUDAH jam tutupnya sendiri. Sudah terbukti terjadi di emulator.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AuthRepository(db);
    // SessionManager membaca `db` global; diarahkan ke database test ini.
    SessionManager.dbOverride = db;

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'kasir-1',
        ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.instance.sesiDicabut.value = null;
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<Shift> shift() =>
      (db.select(db.shifts)..where((s) => s.id.equals('shift-1'))).getSingle();

  test('"Keluar" TIDAK menutup shift', () async {
    await repo.logout(
      userId: 'kasir-1',
      shiftId: 'shift-1',
      akhiriShift: false,
    );

    expect((await shift()).endAt, isNull,
        reason: 'kasir yang cuma meminjam HP rekan harus bisa keluar tanpa '
            'mematikan shift yang masih berjalan di HP-nya sendiri');
  });

  test('"Akhiri Shift" menutup shift', () async {
    await repo.logout(
      userId: 'kasir-1',
      shiftId: 'shift-1',
      akhiriShift: true,
    );

    final s = await shift();
    expect(s.endAt, isNotNull);
    expect(s.syncStatus, 'pending',
        reason: 'penutupannya harus ikut tersinkron ke perangkat lain');
  });

  group('jaring pengaman: shift ditutup dari perangkat lain', () {
    Future<void> masuk({String? shiftId = 'shift-1'}) =>
        SessionManager.instance.setSession(AuthSession.create(
          userId: 'kasir-1',
          username: 'budi',
          role: 'cashier',
          shiftId: shiftId,
          permissions: const ['create_transaction'],
        ));

    test('sesi dibersihkan dan alasannya diumumkan', () async {
      await masuk();

      // HP lain menutup shiftnya; barisnya sampai ke sini lewat sinkron.
      await (db.update(db.shifts)..where((s) => s.id.equals('shift-1')))
          .write(ShiftsCompanion(endAt: Value(DateTime.now())));

      await SessionManager.instance.periksaShiftMasihBerjalan();

      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(SessionManager.instance.sesiDicabut.value,
          contains('diakhiri dari perangkat lain'));
    });

    test('shift yang MASIH terbuka tidak mengganggu siapa pun', () async {
      await masuk();
      await SessionManager.instance.periksaShiftMasihBerjalan();

      expect(SessionManager.instance.isLoggedIn, isTrue);
      expect(SessionManager.instance.sesiDicabut.value, isNull);
    });

    test('shift yang BELUM tersinkron tidak dianggap tertutup', () async {
      // Barisnya belum sampai ke perangkat ini. Itu bukan bukti shiftnya
      // ditutup — menendang kasir keluar karenanya jauh lebih merusak
      // daripada menunggu putaran sinkron berikutnya.
      await masuk(shiftId: 'shift-entah');
      await SessionManager.instance.periksaShiftMasihBerjalan();

      expect(SessionManager.instance.isLoggedIn, isTrue);
      expect(SessionManager.instance.sesiDicabut.value, isNull);
    });

    test('owner tanpa shift tidak pernah tersentuh', () async {
      await masuk(shiftId: null);
      await SessionManager.instance.periksaShiftMasihBerjalan();

      expect(SessionManager.instance.isLoggedIn, isTrue);
    });
  });
}
