import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu kasir tidak boleh punya dua shift terbuka sekaligus.
///
/// ── MASALAH YANG DIKUNCI ──
///
/// Saat login, shift terbuka dicari hanya di database LOKAL. Kalau kasir yang
/// sama login di HP kedua sebelum HP itu sempat menarik shift buatan HP
/// pertama, lahirlah shift KEDUA untuk orang yang sama:
///
///   budi login di HP kasir   -> shift S1 dibuat
///   budi login di HP owner   -> S1 belum tersinkron ke sini -> S2 dibuat
///
/// Akibatnya transaksinya terpecah ke dua shift, dan "Akhiri Shift" hanya
/// menutup salah satunya. Yang lain menggantung "Berlangsung" SELAMANYA — dan
/// sejak halaman Pengeluaran pemilik menampilkan shift yang sedang berjalan,
/// shift hantu itu nangkring terus di sana.
///
/// Kueri lamanya juga tidak punya `orderBy`, jadi kalau ada dua, yang terpilih
/// mengikuti urutan penyimpanan — dan itu bisa BERBEDA di tiap HP. Dua
/// perangkat bisa memakai shift yang berbeda walau datanya sudah sama persis.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthRepository repo;

  const pin = '112233';
  late String salt;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AuthRepository(db);

    salt = CryptoUtils.generateSalt();
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'budi',
          pinHash: CryptoUtils.hashPin(pin, salt),
          salt: salt,
          role: 'cashier',
        ));
  });

  tearDown(() async => db.close());

  Future<void> pasangShift(
    String id, {
    required DateTime mulai,
    DateTime? selesai,
    DateTime? dihapus,
    String userId = 'kasir-1',
  }) =>
      db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: Value(id),
            userId: userId,
            startAt: Value(mulai),
            endAt: Value(selesai),
            deletedAt: Value(dihapus),
          ));

  Future<String?> masuk() async =>
      (await repo.login(username: 'budi', pin: pin))?.shiftId;

  Future<Shift> ambilShift(String id) =>
      (db.select(db.shifts)..where((s) => s.id.equals(id))).getSingle();

  test('dua shift terbuka: yang dipakai SELALU yang paling awal dimulai',
      () async {
    // Sengaja disisipkan terbalik — yang belakangan dimulai justru disimpan
    // lebih dulu. Tanpa `orderBy`, inilah yang akan terpilih.
    await pasangShift('siang', mulai: DateTime(2026, 9, 28, 13));
    await pasangShift('pagi', mulai: DateTime(2026, 9, 28, 8));

    expect(await masuk(), 'pagi',
        reason: 'pilihannya harus pasti dan sama di semua perangkat, '
            'bukan mengikuti urutan penyimpanan');
  });

  test('shift hantu yang KOSONG ditutup', () async {
    await pasangShift('pagi', mulai: DateTime(2026, 9, 28, 8));
    await pasangShift('hantu', mulai: DateTime(2026, 9, 28, 13));

    await masuk();

    final hantu = await ambilShift('hantu');
    expect(hantu.endAt, isNotNull,
        reason: 'shift kosong yang menggantung harus ditutup, bukan dibiarkan '
            'nangkring "Berlangsung" selamanya');
    expect(hantu.syncStatus, 'pending',
        reason: 'penutupannya harus ikut tersinkron ke perangkat lain');
  });

  test('shift kedua yang ADA TRANSAKSINYA tidak disentuh', () async {
    await pasangShift('pagi', mulai: DateTime(2026, 9, 28, 8));
    await pasangShift('dipakai', mulai: DateTime(2026, 9, 28, 13));

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: const Value('trx-1'),
          total: 10000,
          paymentMethod: 'cash',
          orderType: const Value('dine_in'),
          shiftId: const Value('dipakai'),
        ));

    await masuk();

    expect((await ambilShift('dipakai')).endAt, isNull,
        reason: 'shift yang sudah dipakai jualan tidak boleh ditutup dari '
            'belakang layar — angkanya sudah masuk laporan, dan HP lain '
            'mungkin masih aktif memakainya');
  });

  test('shift kedua yang ADA PENGELUARANNYA tidak disentuh', () async {
    await pasangShift('pagi', mulai: DateTime(2026, 9, 28, 8));
    await pasangShift('dipakai', mulai: DateTime(2026, 9, 28, 13));

    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: const Value('exp-1'),
          shiftId: 'dipakai',
          userId: 'kasir-1',
          description: 'Beli gas',
          amount: 25000,
        ));

    await masuk();

    expect((await ambilShift('dipakai')).endAt, isNull);
  });

  test('shift yang sudah dihapus lunak tidak pernah terpilih', () async {
    await pasangShift('terhapus',
        mulai: DateTime(2026, 9, 28, 8), dihapus: DateTime(2026, 9, 28, 9));

    final dipakai = await masuk();

    expect(dipakai, isNot('terhapus'));
    expect(await db.select(db.shifts).get(), hasLength(2),
        reason: 'harus membuat shift baru, bukan menghidupkan yang terhapus');
  });

  test('shift milik kasir LAIN tidak ikut terpilih maupun ditutup', () async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('kasir-2'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await pasangShift('punya-sari',
        mulai: DateTime(2026, 9, 28, 7), userId: 'kasir-2');

    final dipakai = await masuk();

    expect(dipakai, isNot('punya-sari'));
    expect((await ambilShift('punya-sari')).endAt, isNull);
  });

  test('tanpa server, login tetap berhasil dan shift tetap terbuka', () async {
    // Supabase tidak disiapkan sama sekali di test ini. Menanyakan shift ke
    // server BOLEH gagal — yang tidak boleh adalah login ikut gagal. Warung
    // harus tetap melayani saat internet mati.
    final dipakai = await masuk();

    expect(dipakai, isNotNull);
    expect((await ambilShift(dipakai!)).endAt, isNull);
  });
}
