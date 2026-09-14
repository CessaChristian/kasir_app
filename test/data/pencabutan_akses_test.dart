import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci agar penonaktifan kasir benar-benar berlaku pada kasir yang
/// SEDANG memakai aplikasi.
///
/// ── LUBANG YANG DIKUNCI ──
///
/// `is_active` hanya diperiksa di dua tempat: saat login, dan di
/// `restoreSession()` yang HANYA berjalan sekali di `main()`. Selama sesi
/// berlangsung tidak ada satu pun kode yang memeriksanya lagi.
///
/// Akibatnya penonaktifan nyaris tidak berguna: pemilik mencabut akses,
/// datanya sampai ke HP kasir lewat sinkronisasi, dan kasirnya TETAP bisa
/// berjualan tanpa batas waktu selama aplikasinya tidak ditutup. Menekan
/// tombol Home pun tidak cukup — `restoreSession` baru jalan lagi kalau
/// proses aplikasinya benar-benar mati.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('u-budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'u-budi',
      username: 'budi',
      role: 'cashier',
      shiftId: null,
      permissions: const ['create_transaction'],
    ));
    SessionManager.instance.sesiDicabut.value = null;
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.instance.sesiDicabut.value = null;
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<void> setelAktif(bool aktif) => (db.update(db.users)
        ..where((u) => u.id.equals('u-budi')))
      .write(UsersCompanion(isActive: Value(aktif)));

  test('akun masih aktif -> sesi dibiarkan', () async {
    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.isLoggedIn, isTrue);
    expect(SessionManager.instance.sesiDicabut.value, isNull);
  });

  test('akun dinonaktifkan -> sesi DICABUT beserta alasannya', () async {
    await setelAktif(false);

    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.isLoggedIn, isFalse,
        reason: 'inilah yang dulu tidak pernah terjadi selama sesi berjalan');
    expect(SessionManager.instance.sesiDicabut.value,
        'Akses Anda dinonaktifkan oleh pemilik.',
        reason: 'dilempar ke layar login tanpa penjelasan membuat kasir '
            'mengira aplikasinya rusak');
  });

  test('akun dihapus lunak -> sesi dicabut', () async {
    await (db.update(db.users)..where((u) => u.id.equals('u-budi')))
        .write(UsersCompanion(deletedAt: Value(DateTime.now())));

    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.isLoggedIn, isFalse);
    expect(SessionManager.instance.sesiDicabut.value, contains('dihapus'));
  });

  test('baris user lenyap -> sesi dicabut', () async {
    await (db.delete(db.users)..where((u) => u.id.equals('u-budi'))).go();

    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.isLoggedIn, isFalse);
  });

  test('tanpa sesi, tidak melakukan apa-apa', () async {
    await SessionManager.instance.clearSession();
    SessionManager.instance.sesiDicabut.value = null;

    await SessionManager.instance.periksaAkunMasihBerlaku();

    expect(SessionManager.instance.sesiDicabut.value, isNull);
  });
}
