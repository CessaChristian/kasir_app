import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA kedua K3 & K2.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sm = SessionManager.instance;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('k-1'),
          username: 'sari',
          pinHash: 'pin-lama',
          salt: 's',
          role: 'cashier',
        ));
    await sm.setSession(AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: 's-1',
      permissions: const [],
    ));
    await sm.ingatPinMasuk('k-1', 'pin-lama'); // seperti AuthRepository.login
  });

  tearDown(() async {
    await sm.clearSession();
    sm.sesiDicabut.value = null;
    SessionManager.dbOverride = null;
    await db.close();
  });

  group('K3: sesi yang berakhir di tengah pembacaan tidak hidup lagi', () {
    test('muat ulang izin', () async {
      await db.into(db.userPermissions).insert(UserPermissionsCompanion.insert(
            id: 'izin-1',
            userId: 'k-1',
            permissionCode: 'create_transaction',
            enabled: const Value(true),
          ));
      final baca = sm.muatUlangIzin(); // sedang menunggu database
      await sm.clearSession(); // mis. 15 menit tidak disentuh
      await baca;
      expect(sm.isLoggedIn, isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('auth_session'), isNull,
          reason: 'tidak boleh tertulis lagi ke penyimpanan');
    });

    test('periksa akun (nama diganti owner)', () async {
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(username: Value('sari2')));
      final periksa = sm.periksaAkunMasihBerlaku();
      await sm.clearSession();
      await periksa;
      expect(sm.isLoggedIn, isFalse);
    });
  });

  group('K2: Reset PIN mengakhiri sesi yang sedang berjalan', () {
    test('PIN akun yang sedang masuk diganti → keluar dengan pesan', () async {
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(pinHash: Value('pin-baru')));
      await sm.periksaAkunMasihBerlaku();
      expect(sm.isLoggedIn, isFalse);
      expect(sm.sesiDicabut.value, SessionManager.pesanPinDiganti);
    });

    test('login mencatat PIN saat masuk', () async {
      await sm.clearSession();
      final salt = CryptoUtils.generateSalt();
      final hash = await CryptoUtils.hashPinDiLatar('123456', salt);
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(UsersCompanion(pinHash: Value(hash), salt: Value(salt)));
      final sesi =
          await AuthRepository(db).login(username: 'sari', pin: '123456');
      await sm.setSession(sesi!);
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(pinHash: Value('direset-owner')));
      await sm.periksaAkunMasihBerlaku();
      expect(sm.sesiDicabut.value, SessionManager.pesanPinDiganti);
    });

    test('PIN tidak berubah (ganti nama saja) → tetap masuk', () async {
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(username: Value('sari2')));
      await sm.periksaAkunMasihBerlaku();
      expect(sm.isLoggedIn, isTrue);
    });

    test('aplikasi dibuka ulang: PIN saat masuk tetap diingat', () async {
      final p = await SharedPreferences.getInstance();
      final tersimpan = {
        for (final k in p.getKeys()) k: p.get(k)!,
      };
      SharedPreferences.setMockInitialValues(tersimpan.cast());
      await (db.update(db.users)..where((u) => u.id.equals('k-1')))
          .write(const UsersCompanion(pinHash: Value('pin-baru')));
      await sm.restoreSession();
      await sm.periksaAkunMasihBerlaku();
      expect(sm.isLoggedIn, isFalse);
    });
  });
}
