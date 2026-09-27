import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner tidak menjual, dan itu ditegakkan — bukan sekadar disembunyikan.
///
/// ── MASALAH YANG DIKUNCI ──
///
/// `hasPermission` dulu menjawab true untuk owner pada SETIAP izin. Owner
/// memang tidak pernah dibukakan shift (`auth_repository.dart` menolak lewat
/// `user.role != 'owner'`), tapi menjual TIDAK butuh shift — `createSale`
/// menerima `shiftId` yang boleh kosong.
///
/// Akibatnya menu Kasir tetap muncul di HP owner, dan transaksi yang dibuat
/// di sana tersimpan TANPA shift: tidak masuk rekap shift siapa pun, tidak
/// terhitung di laporan per kasir, dan tidak ada yang bisa melihatnya selain
/// daftar transaksi mentah.
///
/// Itu juga sumber nomor nota kembar. Nomor dihitung dari jumlah transaksi
/// hari ini di perangkat MASING-MASING, jadi dua perangkat yang sama-sama
/// boleh menjual pasti bertabrakan — lihat `invoice_number_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  /// Seluruh kode izin yang ada di katalog.
  ///
  /// Sesi owner yang SUNGGUHAN membawa daftar ini — `_getUserPermissions`
  /// mengisinya dari seluruh isi tabel `permissions`. Versi pertama test ini
  /// memakai daftar KOSONG, sehingga lulus walaupun tambalannya tidak
  /// bekerja: `hasPermission` waktu itu membaca daftar sesi, dan daftar
  /// kosong memang tidak memuat `create_transaction`.
  const semuaIzin = <String>[
    'open_close_shift',
    'create_transaction',
    'view_history',
    'view_report',
    'manage_products',
    'manage_cashiers',
    'view_shift_reports',
    'view_all_shifts',
  ];

  Future<void> masukSebagai(String peran, {List<String>? izin}) =>
      SessionManager.instance.setSession(AuthSession.create(
        userId: 'u-1',
        username: peran,
        role: peran,
        shiftId: peran == 'owner' ? null : 'shift-1',
        // Owner tanpa daftar eksplisit = sesi seperti aslinya: membawa SEMUA
        // kode izin. Di situlah tambalannya harus tetap menolak.
        permissions: izin ?? (peran == 'owner' ? semuaIzin : const []),
      ));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('u-1'),
          username: 'cessa',
          pinHash: 'h',
          salt: 's',
          role: 'owner',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'u-1',
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Es Teh',
          price: 5000,
        ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<String> jual() => db.createSale(
        transactionId: 'trx-1',
        paymentMethod: 'cash',
        cashReceived: 5000,
        orderType: 'dine_in',
        kodePerangkat: 'TEST',
        lines: [
          SaleLine(
            productId: 'prod-1',
            productName: 'Es Teh',
            qty: 1,
            priceAtSale: 5000,
          ),
        ],
      );

  test('owner TIDAK punya izin menjual', () async {
    await masukSebagai('owner');
    expect(SessionManager.instance.hasPermission('create_transaction'), isFalse);
  });

  test('owner TIDAK punya izin buka/tutup shift', () async {
    await masukSebagai('owner');
    expect(SessionManager.instance.hasPermission('open_close_shift'), isFalse);
  });

  test('owner tetap punya izin lainnya', () async {
    await masukSebagai('owner');
    for (final izin in const [
      'manage_products',
      'manage_cashiers',
      'view_report',
      'view_history',
      'view_all_shifts',
    ]) {
      expect(SessionManager.instance.hasPermission(izin), isTrue,
          reason: '$izin adalah hak owner dan tidak boleh ikut dicabut');
    }
  });

  test('lapisan database menolak penjualan dari owner', () async {
    await masukSebagai('owner');

    // Bukan cuma disembunyikan dari menu: kalau suatu hari ada jalan lain
    // menuju halaman Kasir, database tetap menolaknya.
    await expectLater(jual(), throwsA(isA<StateError>()));
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('kasir berizin tetap bisa menjual', () async {
    await masukSebagai('cashier', izin: const ['create_transaction']);

    final nota = await jual();
    expect(nota, contains('TEST-0001'));
    expect(await db.select(db.transactions).get(), hasLength(1));
  });
}
