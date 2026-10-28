import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/data/uuid_helper.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci penomoran nota.
///
/// Format lama `TRX/dd/MM/yy/<mikrodetik % 1jt>` bukan nomor urut melainkan
/// enam angka acak yang berulang tiap detik, sehingga dua struk berbeda bisa
/// bernomor sama. Simulasi pada 300 transaksi/hari memperkirakan sekitar 15
/// hari bentrok per tahun — dan itu di SATU perangkat, tanpa sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('owner-1'),
          username: 'owner',
          pinHash: 'h',
          salt: 's',
          role: 'owner',
        ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'owner-1',
        ));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Es Teh',
          price: 5000,
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: 'owner-1',
      username: 'owner',
      role: 'cashier',
      shiftId: null,
      permissions: const ['create_transaction'],
    ));
  });

  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  /// Satu penjualan. Mengembalikan (id transaksi, nomor nota).
  Future<({String id, String nota})> jual() async {
    final id = newUuid();
    final nota = await db.createSale(
      transactionId: id,
      shiftId: 'shift-1',
      cashierUserId: 'owner-1',
      paymentMethod: 'qris',
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Es Teh',
          qty: 1,
          priceAtSale: 5000,
        ),
      ],
      kodePerangkat: 'TEST',
    );
    return (id: id, nota: nota);
  }

  /// Bagian urut saja, dari `CS/kasir/ddMMyy/KODE-NNNN`.
  String urutan(String nota) => nota.split('/').last.split('-').last;

  /// Penanda perangkat saja.
  String kode(String nota) => nota.split('/').last.split('-').first;

  test('nomor nota berurutan mulai dari 0001', () async {
    expect(urutan((await jual()).nota), '0001');
    expect(urutan((await jual()).nota), '0002');
    expect(urutan((await jual()).nota), '0003');
  });

  /// Tanggal buka shift-1 sebagai ddMMyy.
  Future<String> tanggalShift() async {
    final s = await (db.select(db.shifts)..where((t) => t.id.equals('shift-1')))
        .getSingle();
    final b = s.startAt.toLocal();
    String dua(int n) => (n % 100).toString().padLeft(2, '0');
    return '${dua(b.day)}${dua(b.month)}${dua(b.year)}';
  }

  Future<void> nomorKasir(int? n) =>
      (db.update(db.users)..where((u) => u.id.equals('owner-1')))
          .write(UsersCompanion(nomorKasir: Value(n)));

  test('format CS/<kasir>/<tanggal buka shift>/<kode>-<urut>', () async {
    await nomorKasir(1);
    expect((await jual()).nota, 'CS/01/${await tanggalShift()}/TEST-0001');
  });

  test('owner bernomor 00; nomor belum ditarik = XX', () async {
    await nomorKasir(0);
    expect((await jual()).nota, startsWith('CS/00/'));
    await nomorKasir(null);
    expect((await jual()).nota, startsWith('CS/XX/'));
  });

  test('tanggal ikut shift DIBUKA: lewat tengah malam tetap lanjut', () async {
    // Shift dibuka 5 Jan 2025 23.00; penjualan terjadi "sekarang" — tanggal
    // lain (sengaja bukan hari ini, supaya tidak lolos kebetulan).
    await (db.update(db.shifts)..where((t) => t.id.equals('shift-1'))).write(
      ShiftsCompanion(startAt: Value(DateTime(2025, 1, 5, 23))),
    );
    expect((await jual()).nota, 'CS/XX/050125/TEST-0001');
    expect((await jual()).nota, 'CS/XX/050125/TEST-0002');
  });

  test('shift baru di tanggal lain: mulai lagi dari 0001', () async {
    await (db.update(db.shifts)..where((t) => t.id.equals('shift-1'))).write(
      ShiftsCompanion(startAt: Value(DateTime(2026, 10, 17, 16))),
    );
    await jual();
    await jual();
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-2'),
          userId: 'owner-1',
          startAt: Value(DateTime(2026, 10, 18, 16)),
        ));
    final nota = await db.createSale(
      transactionId: newUuid(),
      shiftId: 'shift-2',
      paymentMethod: 'qris',
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Es Teh',
          qty: 1,
          priceAtSale: 5000,
        ),
      ],
      kodePerangkat: 'TEST',
    );
    expect(nota, 'CS/XX/181026/TEST-0001');
  });

  test('nota HP lain dan nota format lama tidak ikut dihitung', () async {
    final tgl = await tanggalShift();
    for (final (id, nota) in [
      ('t-b', 'CS/02/$tgl/B-0007'),
      ('t-lama', 'TRX/17/10/26/TEST-0009'),
    ]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: Value(id),
            invoiceNo: Value(nota),
            total: 1000,
            paymentMethod: 'cash',
          ));
    }
    expect(urutan((await jual()).nota), '0001');
  });

  test('lanjut dari nomor TERBESAR, bukan dari jumlah nota', () async {
    // Nota 0002 HP ini hilang dari database lokal (mis. aturan buang sampah
    // berubah). Dengan menghitung jumlah baris, nota berikutnya jadi 0002
    // lagi — padahal 0003 sudah terbit, dan nomor 0003 akan terpakai dua kali.
    final tgl = await tanggalShift();
    for (final (id, nota) in [
      ('t-1', 'CS/00/$tgl/TEST-0001'),
      ('t-3', 'CS/00/$tgl/TEST-0003'),
    ]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: Value(id),
            invoiceNo: Value(nota),
            total: 1000,
            paymentMethod: 'cash',
          ));
    }
    expect(urutan((await jual()).nota), '0004');
  });

  test('nomor TIDAK dipakai ulang setelah transaksi dihapus', () async {
    await jual();
    final kedua = await jual();
    expect(urutan(kedua.nota), '0002');

    await db.batalkanTransaksi(kedua.id,
        olehUserId: 'owner-1', alasan: 'Salah input');

    // Inti perbaikan: penghitungan mengikutsertakan baris yang sudah ditandai
    // terhapus. Kalau tidak, transaksi berikutnya dapat 0002 lagi dan ada dua
    // struk bernomor sama — persis masalah yang mau dihilangkan.
    expect(urutan((await jual()).nota), '0003',
        reason: 'nomor bekas transaksi terhapus tidak boleh dipakai lagi');
  });

  test('tidak ada nomor kembar pada 50 transaksi berturut-turut', () async {
    final semua = <String>{};
    for (var i = 0; i < 50; i++) {
      semua.add((await jual()).nota);
    }
    expect(semua, hasLength(50), reason: 'setiap struk harus unik');
    expect(semua.map(urutan), contains('0050'));
  });

  test('createSale mengembalikan nomor yang benar-benar tersimpan', () async {
    final hasil = await jual();

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(hasil.id)))
        .getSingle();
    expect(tx.invoiceNo, hasil.nota);
  });

  test('nomor memuat penanda perangkat', () async {
    expect(kode((await jual()).nota), 'TEST');
  });

  test('dua perangkat pada urutan yang sama TIDAK bertabrakan', () async {
    // Inilah tabrakan yang dulu terjadi: nomor dihitung dari jumlah transaksi
    // hari ini di database MASING-MASING perangkat. Dua HP yang sama-sama
    // baru mencatat nol transaksi akan sama-sama menerbitkan nomor ke-1.
    final dariA = (await jual()).nota;

    final dbB = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbB.close);
    await dbB.into(dbB.users).insert(UsersCompanion.insert(
          id: const Value('kasir-1'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await dbB.into(dbB.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-1'),
          userId: 'kasir-1',
        ));
    await dbB.into(dbB.products).insert(ProductsCompanion.insert(
          id: const Value('prod-1'),
          name: 'Es Teh',
          price: 5000,
        ));
    final dariB = await dbB.createSale(
      transactionId: 'trx-b',
      shiftId: 'shift-1',
      paymentMethod: 'cash',
      cashReceived: 50000,
      orderType: 'dine_in',
      lines: [
        SaleLine(
          productId: 'prod-1',
          productName: 'Es Teh',
          qty: 1,
          priceAtSale: 5000,
        ),
      ],
      kodePerangkat: 'B7KM',
    );

    expect(urutan(dariA), urutan(dariB),
        reason: 'urutannya memang sama — itulah sumber tabrakannya');
    expect(dariA, isNot(dariB),
        reason: 'penanda perangkat yang membedakannya');
  });
}
