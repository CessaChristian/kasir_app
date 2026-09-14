import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v21 SUNGGUHAN di atas database berbentuk v20.
///
/// ── CACAT YANG DIKUNCI ──
///
/// Migrasi mula-mula hanya menghapus baris dari `permissions`, mengandalkan
/// `ON DELETE CASCADE` membuang baris `user_permissions` yang menunjuknya.
///
/// CASCADE TIDAK berlaku di sana: SQLite mematikan penegakan foreign key
/// sepanjang migrasi. Akibatnya izin kasir menyisakan baris yang menunjuk kode
/// yang sudah tidak ada — `PRAGMA foreign_key_check` melaporkan dua
/// pelanggaran, dan budi tetap memegang 3 baris izin padahal seharusnya 1.
///
/// Test ini WAJIB berjalan di atas database lama, bukan database baru: pada
/// database baru blok migrasinya tidak pernah dieksekusi, sehingga cacatnya
/// mustahil terlihat. Percobaan pertama test ini melakukan persis kesalahan
/// itu dan lulus tanpa menguji apa pun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late String jalur;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('uji_v21');
    jalur = '${folder.path}/v20.sqlite';
    _bangunV20(jalur);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test('v21 membuang izin yang dipatenkan TANPA meninggalkan baris yatim',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(File(jalur)));

    // Membaca memicu migrasinya.
    final katalog = await db.select(db.permissions).get();
    final izin = await db.select(db.userPermissions).get();
    final pelanggaran =
        await db.customSelect('PRAGMA foreign_key_check').get();
    await db.close();

    expect(katalog, hasLength(8), reason: '12 kode menjadi 8');
    for (final mati in const [
      'edit_own_expense',
      'edit_any_expense',
      'delete_own_transaction',
      'delete_any_transaction',
    ]) {
      expect(katalog.map((p) => p.code), isNot(contains(mati)));
    }

    expect(izin, hasLength(1),
        reason: 'dua baris izin budi yang menunjuk kode terhapus WAJIB ikut '
            'terbuang — CASCADE tidak menolong di dalam migrasi');
    expect(izin.single.permissionCode, 'create_transaction');

    expect(pelanggaran, isEmpty,
        reason: 'baris yatim muncul di sini kalau baris anak tidak dibuang '
            'secara eksplisit');

    expect(katalog.firstWhere((p) => p.code == 'open_close_shift').name,
        'Buka & Tutup Shift',
        reason: 'nama berbahasa Inggris pada pemasangan LAMA harus ikut '
            'ditimpa, bukan hanya berlaku untuk pemasangan baru');
  });
}

/// Membangun database berbentuk v20: sudah punya kolom sync, tapi masih memuat
/// 12 kode izin — termasuk empat yang dipatenkan di v21.
void _bangunV20(String jalur) {
  final db = sqlite3.open(jalur);
  db.execute('''
    PRAGMA foreign_keys = OFF;

    CREATE TABLE users (
      id TEXT NOT NULL PRIMARY KEY, username TEXT NOT NULL UNIQUE,
      pin_hash TEXT NOT NULL, salt TEXT NOT NULL, role TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      deleted_at INTEGER, sync_status TEXT NOT NULL DEFAULT 'synced',
      recovery_hash TEXT, recovery_salt TEXT, recovery_created_at INTEGER,
      recovery_used_at INTEGER,
      recovery_attempts INTEGER NOT NULL DEFAULT 0,
      recovery_locked_until INTEGER,
      login_attempts INTEGER NOT NULL DEFAULT 0,
      login_locked_until INTEGER
    );

    CREATE TABLE permissions (
      code TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
      description TEXT NOT NULL
    );

    CREATE TABLE user_permissions (
      id TEXT NOT NULL PRIMARY KEY, user_id TEXT NOT NULL,
      permission_code TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
      deleted_at INTEGER, sync_status TEXT NOT NULL DEFAULT 'pending',
      UNIQUE(user_id, permission_code),
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY(permission_code) REFERENCES permissions(code) ON DELETE CASCADE
    );

    INSERT INTO users (id,username,pin_hash,salt,role) VALUES
      ('u-owner','owner','h','s','owner'),
      ('u-budi','budi','h','s','cashier');

    INSERT INTO permissions (code,name,description) VALUES
      ('open_close_shift','Open/Close Shift','Ability to start and end shifts'),
      ('create_transaction','Create Transaction','x'),
      ('view_history','View Transaction History','x'),
      ('view_report','View Reports','x'),
      ('manage_products','Manage Products','x'),
      ('manage_cashiers','Manage Cashiers','x'),
      ('view_shift_reports','View Shift Reports','x'),
      ('view_all_shifts','View All Shifts','x'),
      ('edit_own_expense','Edit Own Expense','x'),
      ('edit_any_expense','Edit Any Expense','x'),
      ('delete_own_transaction','Delete Own Transaction','x'),
      ('delete_any_transaction','Delete Any Transaction','x');

    INSERT INTO user_permissions (id,user_id,permission_code,enabled) VALUES
      ('i1','u-budi','create_transaction',1),
      ('i2','u-budi','edit_any_expense',1),
      ('i3','u-budi','delete_any_transaction',1);

    PRAGMA user_version = 20;
  ''');
  db.dispose();
}
