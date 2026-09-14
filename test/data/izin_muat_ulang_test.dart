import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/uuid_helper.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci agar izin yang baru turun dari server langsung berlaku, tanpa
/// pengguna harus keluar dan masuk lagi.
///
/// ── KENAPA INI PERLU ──
///
/// Daftar izin dibaca SEKALI saat login lalu disimpan di dalam sesi.
/// Sinkronisasi memperbarui tabelnya, tapi sesi yang sedang berjalan tidak
/// tahu apa-apa.
///
/// Terlihat langsung saat pengujian dua emulator: pemilik memberi izin
/// `view_report` kepada budi, izinnya sampai ke HP kasir, tapi menu Laporan
/// TETAP tidak muncul. Baru muncul setelah budi keluar dan masuk lagi — dan
/// tidak ada apa pun di layar yang memberi tahu bahwa itu syaratnya.
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
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<void> beriIzin(String kode) =>
      db.into(db.userPermissions).insertOnConflictUpdate(
            UserPermissionsCompanion.insert(
              id: uuidTurunan('u-budi:$kode'),
              userId: 'u-budi',
              permissionCode: kode,
              enabled: const Value(true),
            ),
          );

  test('izin baru langsung berlaku tanpa login ulang', () async {
    expect(SessionManager.instance.hasPermission('view_report'), isFalse);

    await beriIzin('create_transaction');
    await beriIzin('view_report');
    await SessionManager.instance.muatUlangIzin();

    expect(SessionManager.instance.hasPermission('view_report'), isTrue,
        reason: 'inilah yang dulu butuh keluar-masuk aplikasi dulu');
  });

  test('izin yang DICABUT juga langsung berlaku', () async {
    // Arah ini lebih penting daripada penambahan: izin yang dicabut pemilik
    // tapi masih hidup di HP kasir jauh lebih berbahaya daripada izin yang
    // terlambat menyala.
    await beriIzin('create_transaction');
    await beriIzin('view_report');
    await SessionManager.instance.muatUlangIzin();
    expect(SessionManager.instance.hasPermission('view_report'), isTrue);

    await db.into(db.userPermissions).insertOnConflictUpdate(
          UserPermissionsCompanion.insert(
            id: uuidTurunan('u-budi:view_report'),
            userId: 'u-budi',
            permissionCode: 'view_report',
            enabled: const Value(false),
          ),
        );
    await SessionManager.instance.muatUlangIzin();

    expect(SessionManager.instance.hasPermission('view_report'), isFalse);
  });

  test('layar diberi tahu HANYA kalau izinnya benar-benar berubah', () async {
    await beriIzin('create_transaction');
    final awal = SessionManager.instance.izinBerubah.value;

    await SessionManager.instance.muatUlangIzin();
    expect(SessionManager.instance.izinBerubah.value, awal,
        reason: 'daftarnya sama — jangan menggambar ulang layar tanpa alasan');

    await beriIzin('view_history');
    await SessionManager.instance.muatUlangIzin();
    expect(SessionManager.instance.izinBerubah.value, greaterThan(awal));
  });

  test('owner dilewati — izinnya tidak pernah dari tabel', () async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('u-owner'),
          username: 'owner',
          pinHash: 'h',
          salt: 's',
          role: 'owner',
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'u-owner',
      username: 'owner',
      role: 'owner',
      shiftId: null,
      permissions: const [],
    ));
    final awal = SessionManager.instance.izinBerubah.value;

    await SessionManager.instance.muatUlangIzin();

    expect(SessionManager.instance.izinBerubah.value, awal);
    expect(SessionManager.instance.hasPermission('apa_saja'), isTrue,
        reason: 'owner selalu true, tanpa perlu satu baris pun di tabel');
  });
}
