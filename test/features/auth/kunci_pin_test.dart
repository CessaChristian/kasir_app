import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/recovery/models/recovery_result.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kunci salah PIN yang TIDAK bergantung jam HP (revisi QA B2).
///
/// Kunci waktu yang lama ("coba lagi 5 menit lagi") bisa dilewati dengan
/// memajukan jam HP di Pengaturan, sehingga PIN 6 digit bisa ditebak habis.
/// Sekarang 10 kali salah berturut-turut mengunci akun sampai PIN-nya dibuat
/// ulang — berapa pun jam HP-nya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthRepository repo;
  const pinOwner = '135790';
  const pinKasir = '246810';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = AuthRepository(db);
    for (final (id, nama, role, pin) in [
      ('o-1', 'owner', 'owner', pinOwner),
      ('k-1', 'sari', 'cashier', pinKasir),
    ]) {
      final salt = CryptoUtils.generateSalt();
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: nama,
            pinHash: CryptoUtils.hashPin(pin, salt),
            salt: salt,
            role: role,
          ));
    }
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<User> akun(String id) =>
      (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();

  /// Salah PIN [kali] kali, dan setiap kunci waktunya dianggap sudah lewat —
  /// persis seperti orang yang memajukan jam HP-nya.
  Future<void> tebakSalah(String username, String id, int kali) async {
    for (var i = 0; i < kali; i++) {
      await (db.update(db.users)..where((u) => u.id.equals(id))).write(
        const UsersCompanion(loginLockedUntil: Value(null)),
      );
      expect(await repo.login(username: username, pin: '000000'), isNull);
    }
    await (db.update(db.users)..where((u) => u.id.equals(id))).write(
      const UsersCompanion(loginLockedUntil: Value(null)),
    );
  }

  test('kasir: 10 kali salah → PIN benar pun ditolak, walau jam dimajukan',
      () async {
    await tebakSalah('sari', 'k-1', AuthRepository.batasSalahPin);
    await expectLater(
      repo.login(username: 'sari', pin: pinKasir),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'pesan', AuthRepository.pesanKasirTerkunci)),
    );
    expect(AuthRepository.pesanKasirTerkunci, contains('Kelola Kasir'));
  });

  test('9 kali salah lalu benar: masuk, dan hitungannya kembali nol', () async {
    await tebakSalah('sari', 'k-1', AuthRepository.batasSalahPin - 1);
    expect(await repo.login(username: 'sari', pin: pinKasir), isNotNull);
    expect((await akun('k-1')).loginAttempts, 0);
  });

  test('owner: 10 kali salah → diarahkan ke kode recovery', () async {
    await tebakSalah('owner', 'o-1', AuthRepository.batasSalahPin);
    await expectLater(
      repo.login(username: 'owner', pin: pinOwner),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'pesan', contains('Lupa PIN Owner'))),
    );
  });

  test('Reset PIN dari Kelola Kasir membuka kunci kasir', () async {
    await tebakSalah('sari', 'k-1', AuthRepository.batasSalahPin);
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'o-1',
      username: 'owner',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ));
    await CashierRepository(db, terhubung: () async => true)
        .resetCashierPin('k-1', '135791');
    await SessionManager.instance.clearSession();
    expect(await repo.login(username: 'sari', pin: '135791'), isNotNull);
  });

  test('kode recovery membuka kunci login owner (B7a)', () async {
    final kode = await repo.generateAndStoreRecoveryCodeForOwner('o-1');
    await tebakSalah('owner', 'o-1', AuthRepository.batasSalahPin);
    final hasil = await repo.resetOwnerPinWithRecoveryCode(
      recoveryCode: kode,
      newPin: '975310',
    );
    expect(hasil.isSuccess, isTrue);
    expect(await repo.login(username: 'owner', pin: '975310'), isNotNull,
        reason: 'langsung bisa masuk, tidak menunggu kunci habis');
  });

  test('"Buat kode recovery baru" ikut menghitung salah PIN owner', () async {
    for (var i = 0; i < AuthRepository.batasSalahPin; i++) {
      final r = await repo.regenerateOwnerRecoveryCode('000000');
      expect(r.type, RecoveryResultType.pinMismatch);
      expect(r.message, 'PIN salah');
    }
    final r = await repo.regenerateOwnerRecoveryCode(pinOwner);
    expect(r.type, RecoveryResultType.locked,
        reason: 'PIN benar pun ditolak sesudah 10 kali salah');
    expect(r.message, AuthRepository.pesanOwnerTerkunci);
  });

  group('username tidak bisa ditebak dari pesannya (B7b)', () {
    test('username yang tidak ada dijawab sama dengan PIN salah', () async {
      expect(await repo.login(username: 'tidakada', pin: '000000'), isNull);
      expect(await repo.login(username: 'sari', pin: '000000'), isNull);
    });

    test('akun nonaktif: PIN salah dijawab biasa, PIN benar baru diberi '
        'tahu', () async {
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(isActive: Value(false)));
      expect(await repo.login(username: 'sari', pin: '000000'), isNull);
      await expectLater(
        repo.login(username: 'sari', pin: pinKasir),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'pesan', 'Akun Anda dinonaktifkan oleh pemilik.')),
      );
    });
  });
}
