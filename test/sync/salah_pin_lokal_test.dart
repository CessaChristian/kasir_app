import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA kedua S2 — hitungan salah PIN milik HP masing-masing.
///
/// Dulu ikut sinkron: sari yang terkunci di HP kasir lepas kuncinya begitu
/// owner mengganti namanya di HP owner (baris terkirim dengan hitungan 0),
/// dan salah PIN di satu HP mengunci akun di semua HP. Satu-satunya yang
/// boleh melepas kunci dari HP lain adalah Reset PIN — terlihat dari hash
/// PIN yang berubah.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;
  final terkirim = <Map<String, dynamic>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    terkirim.clear();
    mesin = SyncEngine(db)
      ..pengirimUntukTest = (tabel, baris) async {
        if (tabel == 'users') terkirim.addAll(baris);
      };
  });
  tearDown(() => db.close());

  Map<String, dynamic> barisServer({
    String pinHash = 'h',
    String username = 'sari',
    int salah = 0,
    String? kunci,
    String jam = '2030-01-01T10:00:00Z',
  }) => {
    'id': 'k-1',
    'username': username,
    'pin_hash': pinHash,
    'salt': 's',
    'role': 'cashier',
    'is_active': true,
    'recovery_hash': null,
    'recovery_salt': null,
    'recovery_created_at': null,
    'recovery_used_at': null,
    'recovery_attempts': 0,
    'recovery_locked_until': null,
    'login_attempts': salah,
    'login_locked_until': kunci,
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': jam,
    'server_urut': jam,
  };

  Future<void> tarik(Map<String, dynamic> baris) async {
    mesin.penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
        tabel == 'users' && setelah == null ? [baris] : const [];
    await mesin.tarikTabel('users');
  }

  Future<void> sariTerkunciDiHpIni() => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: const Value('k-1'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
          loginAttempts: const Value(10),
          loginLockedUntil: Value(DateTime(2030)),
          syncStatus: const Value('synced'),
        ),
      );

  Future<User> sari() =>
      (db.select(db.users)..where((u) => u.id.equals('k-1'))).getSingle();

  test('kirim: hitungan & kunci salah PIN TIDAK ikut', () async {
    await sariTerkunciDiHpIni();
    await (db.update(db.users)..where((u) => u.id.equals('k-1'))).write(
      const UsersCompanion(syncStatus: Value('pending')),
    );
    await mesin.dorongSemua();
    final b = terkirim.single;
    expect(b.containsKey('login_attempts'), isFalse);
    expect(b.containsKey('login_locked_until'), isFalse);
  });

  test('owner ganti nama (PIN sama, hitungan server 0): kunci TETAP', () async {
    await sariTerkunciDiHpIni();
    await tarik(barisServer(username: 'sari2'));
    final u = await sari();
    expect(u.username, 'sari2');
    expect(u.loginAttempts, 10);
    expect(u.loginLockedUntil, isNotNull);
  });

  test('salah PIN di HP lain (server 10): HP ini TIDAK ikut terkunci',
      () async {
    await tarik(barisServer());
    await tarik(barisServer(
      salah: 10,
      kunci: '2030-01-01T00:00:00Z',
      jam: '2030-01-02T10:00:00Z',
    ));
    final u = await sari();
    expect(u.loginAttempts, 0);
    expect(u.loginLockedUntil, isNull);
  });

  test('Reset PIN (hash berubah): kunci di HP ini lepas', () async {
    await sariTerkunciDiHpIni();
    await tarik(barisServer(pinHash: 'h-baru'));
    final u = await sari();
    expect(u.pinHash, 'h-baru');
    expect(u.loginAttempts, 0);
    expect(u.loginLockedUntil, isNull);
  });
}
