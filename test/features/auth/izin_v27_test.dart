import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/shared/auth/cakupan_riwayat.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Revisi izin v27.
///
/// - Kelola Kasir jadi hak PATEN owner — kasir yang (dulu) diberi izin
///   `manage_cashiers` tetap ditolak di setiap fungsi, bukan hanya di menu.
/// - `view_history` berganti arti: bukan lagi "boleh membuka Riwayat", tapi
///   "boleh melihat shift-shift yang sudah lewat". Riwayat dulu menampilkan
///   SEMUA transaksi SEMUA kasir kepada setiap pemegang izin itu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  Future<void> masuk(String id, String role,
          {String? shiftId, List<String> izin = const []}) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: id,
        username: id,
        role: role,
        shiftId: shiftId,
        permissions: izin,
      ));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    for (final (id, role) in [
      ('owner', 'owner'),
      ('budi', 'cashier'),
      ('sari', 'cashier'),
    ]) {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: id,
            pinHash: 'h',
            salt: 's',
            role: role,
          ));
    }
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  group('Kelola Kasir hak paten owner', () {
    test('kasir yang memegang izin lama manage_cashiers tetap ditolak',
        () async {
      await masuk('budi', 'cashier', izin: const ['manage_cashiers']);
      final repo = CashierRepository(db,
          namaDipakaiDiServer: (_, _) async => false);

      await expectLater(
          repo.createCashier(username: 'baru', pin: '727272'),
          throwsA(isA<StateError>()));
      await expectLater(repo.gantiNamaKasir('sari', 'sarii'),
          throwsA(isA<StateError>()));
      await expectLater(repo.toggleCashierStatus('sari', false),
          throwsA(isA<StateError>()));
      await expectLater(repo.resetCashierPin('sari', '123456'),
          throwsA(isA<StateError>()));
    });

    test('owner tetap bisa', () async {
      await masuk('owner', 'owner');
      final repo = CashierRepository(db,
          namaDipakaiDiServer: (_, _) async => false);

      await repo.gantiNamaKasir('sari', 'sarii');
      await repo.toggleCashierStatus('sari', false);
    });
  });

  group('cakupan riwayat', () {
    setUp(() async {
      for (final (id, user) in [('s-budi-lama', 'budi'), ('s-budi', 'budi'),
                                ('s-sari', 'sari')]) {
        await db.into(db.shifts).insert(
            ShiftsCompanion.insert(id: Value(id), userId: user));
      }
      for (final (id, kasir, shift) in [
        ('t-budi-lama', 'budi', 's-budi-lama'),
        ('t-budi', 'budi', 's-budi'),
        ('t-sari', 'sari', 's-sari'),
      ]) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: Value(id),
              cashierUserId: Value(kasir),
              shiftId: Value(shift),
              total: 10000,
              paymentMethod: 'cash',
            ));
      }
    });

    Future<List<String>> lihat() async {
      final daftar = await SalesRepository(db)
          .watchRiwayat(CakupanRiwayat.dariSesi())
          .first;
      return daftar.map((t) => t.id).toList()..sort();
    }

    test('owner melihat semua transaksi semua kasir', () async {
      await masuk('owner', 'owner');
      expect(await lihat(), ['t-budi', 't-budi-lama', 't-sari']);
    });

    test('kasir TANPA izin hanya melihat shift yang sedang berjalan',
        () async {
      await masuk('budi', 'cashier', shiftId: 's-budi');
      expect(await lihat(), ['t-budi'],
          reason: 'shift lama dan transaksi kasir lain tidak boleh tampil');
    });

    test('shift baru dimulai dari kosong', () async {
      await db.into(db.shifts).insert(
          ShiftsCompanion.insert(id: const Value('s-budi-baru'), userId: 'budi'));
      await masuk('budi', 'cashier', shiftId: 's-budi-baru');
      expect(await lihat(), isEmpty);
    });

    test('kasir tanpa shift berjalan tidak melihat apa pun', () async {
      await masuk('budi', 'cashier');
      expect(await lihat(), isEmpty);
    });

    test('kasir DENGAN izin melihat semua miliknya sendiri, bukan kasir lain',
        () async {
      await masuk('budi', 'cashier',
          shiftId: 's-budi', izin: const ['view_history']);
      expect(await lihat(), ['t-budi', 't-budi-lama'],
          reason: 'dulu pemegang izin ini melihat transaksi SEMUA kasir');
    });
  });

  test('migrasi v27 membuang dua izin paten tanpa baris yatim', () async {
    final folder = Directory.systemTemp.createTempSync('uji_v27');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v26.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama.into(lama.users).insert(UsersCompanion.insert(
          id: const Value('u-budi'),
          username: 'budi',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await lama.close();

    // Keadaan v26: dua kode itu masih ada di katalog dan dipegang budi.
    final mentah = sqlite3.open(jalur);
    for (final kode in ['manage_cashiers', 'view_shift_reports']) {
      mentah.execute(
          "INSERT INTO permissions (code, name, description) VALUES (?, 'x', 'x')",
          [kode]);
    }
    for (final kode in ['manage_cashiers', 'view_shift_reports', 'view_history']) {
      mentah.execute(
          "INSERT INTO user_permissions (id, user_id, permission_code, enabled) "
          "VALUES (?, 'u-budi', ?, 1)",
          ['izin-$kode', kode]);
    }
    mentah.execute(
        "UPDATE permissions SET name = 'Lihat Riwayat Transaksi' "
        "WHERE code = 'view_history'");
    mentah.execute('PRAGMA user_version = 26');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final katalog = await baru.select(baru.permissions).get();
    final izin = await baru.select(baru.userPermissions).get();
    final pelanggaran =
        await baru.customSelect('PRAGMA foreign_key_check').get();
    await baru.close();

    expect(katalog.map((p) => p.code),
        isNot(anyOf(contains('manage_cashiers'), contains('view_shift_reports'))));
    expect(katalog, hasLength(6));
    expect(katalog.firstWhere((p) => p.code == 'view_history').name,
        'Lihat Riwayat Lengkap',
        reason: 'arti barunya harus terbaca di halaman Izin Akses');
    expect(izin.map((i) => i.permissionCode), ['view_history'],
        reason: 'view_history dicabut lewat server, bukan di sini');
    expect(pelanggaran, isEmpty);
  });
}
