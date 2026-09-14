import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/data/uuid_helper.dart';
import 'package:kasir_app/features/auth/repositories/permission_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci agar izin kasir tidak lagi hilang saat HP dipasang ulang.
///
/// ── BUG YANG DIKUNCI (QA-07) ──
///
/// Tabel `user_permissions` lahir sebelum aturan sinkronisasi ada: kunci
/// gabungan, tanpa `updated_at`, tanpa `sync_status`. Jadi ia tidak pernah
/// bisa ikut disinkronkan, dan izin kasir hanya hidup di HP tempat owner
/// mengaturnya.
///
/// Terlihat langsung saat menguji pemasangan baru: kasir `budi` login di HP
/// yang baru dipasang, dan "Akses Cepat" hanya berisi Pengeluaran. Tidak ada
/// menu Kasir — kasirnya tidak bisa berjualan sama sekali, dan owner tidak
/// akan mengerti kenapa karena di HP-nya semuanya terlihat normal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> pasangUser(String nama, String role) async {
    final id = 'u-$nama';
    await db.into(db.users).insert(UsersCompanion.insert(
          id: Value(id),
          username: nama,
          pinHash: 'h',
          salt: 's',
          role: role,
        ));
    return id;
  }

  /// Lewat repository sungguhan, bukan menulis langsung ke tabel.
  ///
  /// Percobaan pertama test ini menulis langsung, dan lolos padahal
  /// `sync_status` tidak pernah dikembalikan ke 'pending' — artinya ia menguji
  /// helper-nya sendiri, bukan jalur yang benar-benar dipakai aplikasi.
  Future<void> beriIzin(String userId, String kode, bool nyala) =>
      PermissionRepository(db).setUserPermission(
        userId: userId,
        permissionCode: kode,
        enabled: nyala,
      );

  test('izin kasir ikut antre kirim — inilah yang dulu tidak pernah terjadi',
      () async {
    final uid = await pasangUser('budi', 'cashier');
    await beriIzin(uid, 'create_transaction', true);

    final tertunda = await (db.select(db.userPermissions)
          ..where((t) => t.syncStatus.equals('pending')))
        .get();

    expect(tertunda, hasLength(1),
        reason: 'tanpa kolom sync_status, baris ini tidak pernah terlihat oleh '
            'mesin sync dan izinnya tidak pernah sampai ke HP kasir');
  });

  test('user_permissions ada di daftar tabel yang disinkronkan', () async {
    // Penjaga langsung terhadap QA-07: kolomnya boleh lengkap, tapi kalau
    // tabelnya tidak didaftarkan, tetap tidak ada yang mengirimkannya.
    final mesin = SyncEngine(db)..pengirimUntukTest = (_, _) async {};
    final uid = await pasangUser('budi', 'cashier');
    await beriIzin(uid, 'create_transaction', true);

    final (terkirim, gagal) = await mesin.dorongSemua();

    expect(gagal, isEmpty);
    expect(terkirim, greaterThan(0),
        reason: 'user_permissions harus ikut terdorong, bukan dilewati');

    final sesudah = await (db.select(db.userPermissions)
          ..where((t) => t.syncStatus.equals('pending')))
        .get();
    expect(sesudah, isEmpty, reason: 'sudah terkirim, tidak boleh mengantre lagi');
  });

  test('id TURUNAN — dua perangkat menghasilkan baris yang sama', () async {
    // Kalau id-nya acak, HP owner dan HP kasir yang sama-sama menyetel izin
    // yang sama menghasilkan dua baris berbeda untuk satu pasangan. Batasan
    // unik menolak yang kedua, dan barisnya tertahan selamanya tanpa sebab
    // yang terlihat di layar.
    const uid = 'u-budi';
    const kode = 'create_transaction';
    expect(uuidTurunan('$uid:$kode'), uuidTurunan('$uid:$kode'));
    expect(uuidTurunan('$uid:$kode'), isNot(uuidTurunan('$uid:view_history')));
  });

  test('pasangan user+izin tidak bisa ganda', () async {
    final uid = await pasangUser('budi', 'cashier');
    await beriIzin(uid, 'create_transaction', true);
    await beriIzin(uid, 'create_transaction', false);

    final semua = await db.select(db.userPermissions).get();
    expect(semua, hasLength(1), reason: 'menimpa, bukan menambah baris kedua');
    expect(semua.first.enabled, isFalse, reason: 'nilai terbaru yang berlaku');
  });

  test('mematikan izin ikut tersebar, bukan hanya menyalakan', () async {
    // Kalau hanya penyalaan yang tersinkron, izin yang DICABUT owner akan
    // tetap hidup di HP kasir — jauh lebih berbahaya daripada izin yang
    // terlambat menyala.
    final uid = await pasangUser('budi', 'cashier');
    await beriIzin(uid, 'view_report', true);
    await db.customUpdate("UPDATE user_permissions SET sync_status='synced'");

    await beriIzin(uid, 'view_report', false);

    final tertunda = await (db.select(db.userPermissions)
          ..where((t) => t.syncStatus.equals('pending')))
        .get();
    expect(tertunda, hasLength(1));
    expect(tertunda.first.enabled, isFalse);
  });

  test('daftar izin bawaan kasir berisi tepat empat yang disepakati', () {
    expect(izinBawaanKasir, [
      'open_close_shift',
      'create_transaction',
      'view_history',
      'view_shift_reports',
    ]);
  });

  test('view_all_shifts BUKAN bawaan — kasir hanya lihat shift sendiri', () {
    // Cakupan halaman Pantau Shift dijaga izin terpisah ini. Kalau ikut
    // diberikan, kasir bisa melihat shift dan pendapatan kasir lain.
    expect(izinBawaanKasir, isNot(contains('view_all_shifts')));
    expect(izinBawaanKasir, isNot(contains('view_report')));
    expect(izinBawaanKasir, isNot(contains('manage_products')));
    expect(izinBawaanKasir, isNot(contains('manage_cashiers')));
  });
}
