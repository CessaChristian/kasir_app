import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v39 — nomor kasir di nomor nota (`CS/01/...`). Nomornya dibagikan server
/// (supabase/nomor_nota.sql) dan ditarik ke HP lewat sinkron biasa.
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

  Map<String, dynamic> barisServer(String id, {Object? nomor = _tanpa}) => {
    'id': id,
    'username': 'sari',
    'pin_hash': 'h',
    'salt': 's',
    'role': 'cashier',
    'is_active': true,
    'recovery_hash': null,
    'recovery_salt': null,
    'recovery_created_at': null,
    'recovery_used_at': null,
    'recovery_attempts': 0,
    'recovery_locked_until': null,
    'login_attempts': 0,
    'login_locked_until': null,
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': '2026-10-17T10:00:00Z',
    'server_urut': '2026-10-17T10:00:00Z',
    if (nomor != _tanpa) 'nomor_kasir': nomor,
  };

  Future<int?> nomorLokal(String id) async => (await (db.select(
    db.users,
  )..where((u) => u.id.equals(id))).getSingle()).nomorKasir;

  test('tarik: nomor kasir dari server tersimpan di HP', () async {
    mesin.penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
        tabel == 'users' && setelah == null
        ? [barisServer('k-1', nomor: 3)]
        : const [];
    await mesin.tarikTabel('users');
    expect(await nomorLokal('k-1'), 3);
  });

  test('tarik dari server lama (tanpa kolom): tidak gagal', () async {
    mesin.penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async =>
        tabel == 'users' && setelah == null ? [barisServer('k-1')] : const [];
    await mesin.tarikTabel('users');
    expect(await nomorLokal('k-1'), isNull);
  });

  test('kirim: nomor ikut kalau ada, TIDAK dikirim kalau kosong', () async {
    for (final (id, nomor) in [('k-ada', 2), ('k-kosong', null)]) {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: Value(id),
              username: id,
              pinHash: 'h',
              salt: 's',
              role: 'cashier',
              nomorKasir: Value(nomor),
            ),
          );
    }
    await mesin.dorongSemua();
    final ada = terkirim.firstWhere((b) => b['id'] == 'k-ada');
    final kosong = terkirim.firstWhere((b) => b['id'] == 'k-kosong');
    expect(ada['nomor_kasir'], 2);
    expect(
      kosong.containsKey('nomor_kasir'),
      isFalse,
      reason: 'null akan menimpa nomor yang sudah dibagikan server',
    );
  });

  test('migrasi v38 → v39: kolom nomor_kasir ditambah, akun utuh', () async {
    final folder = Directory.systemTemp.createTempSync('uji_v39');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v38.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama
        .into(lama.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    await lama.close();

    final mentah = sqlite3.open(jalur);
    mentah.execute('ALTER TABLE users DROP COLUMN nomor_kasir');
    mentah.execute('PRAGMA user_version = 38');
    mentah.close();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baru.close);
    final kolom =
        (await baru
                .customSelect("SELECT name FROM pragma_table_info('users')")
                .get())
            .map((r) => r.read<String>('name'));
    expect(kolom, contains('nomor_kasir'));
    final u = await baru.select(baru.users).getSingle();
    expect((u.username, u.nomorKasir), ('sari', null));
  });
}

const _tanpa = Object();
