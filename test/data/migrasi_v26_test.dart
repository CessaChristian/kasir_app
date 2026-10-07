import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Menjalankan migrasi v26 SUNGGUHAN: kolom `users.deleted_at` dicopot.
///
/// Akun tidak pernah dihapus (satu akun = satu orang), jadi kolom itu tidak
/// punya arti lagi. Yang wajib dijaga: tabel `users` ditunjuk banyak tabel
/// lain — terutama `user_permissions` yang ikut terbuang kalau barisnya
/// dianggap terhapus — jadi mencopot kolom tidak boleh menyentuh isinya.
///
/// Database v25 dibuat dari database terbaru yang diberi kembali kolom itu
/// lalu nomor versinya diturunkan; selebihnya skema v25 dan v26 sama.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late String jalur;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('uji_v26');
    jalur = '${folder.path}/v25.sqlite';
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test('v26 mencopot users.deleted_at tanpa menyentuh akun dan izinnya',
      () async {
    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.users).insert(UsersCompanion.insert(
          id: const Value('u-budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await lama.into(lama.userPermissions).insert(
          UserPermissionsCompanion.insert(
            id: 'izin-1',
            userId: 'u-budi',
            permissionCode: 'create_transaction',
          ),
        );
    await lama.close();

    final mentah = sqlite3.open(jalur);
    // Skema terbaru (v35) sudah punya `deleted_at` — keadaan v25 juga punya.
    mentah.execute('PRAGMA user_version = 25');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final kolom = await baru
        .customSelect("SELECT name FROM pragma_table_info('users')")
        .get();
    final akun = await baru.select(baru.users).get();
    final izin = await baru.select(baru.userPermissions).get();
    await baru.close();

    // v26 mencopot `deleted_at` lama (tak pernah diisi), lalu v35 memasang
    // kolom baru bernama sama dengan arti baru: akun DIHAPUS (keputusan
    // owner 2026-10-07). Yang penting: tidak ada akun yang ikut terhapus.
    expect(kolom.map((r) => r.read<String>('name')), contains('deleted_at'));
    expect(akun.single.username, 'budi');
    expect(akun.single.deletedAt, isNull,
        reason: 'nilai lama tidak terbawa — akun tidak tiba-tiba terhapus');
    expect(izin, hasLength(1),
        reason: 'izin kasir ikut lenyap kalau tabel induknya dibangun ulang');
  });
}
