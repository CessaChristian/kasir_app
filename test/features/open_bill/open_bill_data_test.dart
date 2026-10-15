import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/history/models/kelompok_riwayat.dart';
import 'package:kasir_app/features/open_bill/models/isi_bill.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Open Bill (v38): simpan → muat ke keranjang → bayar / hapus. Bill milik
/// shift, harga mengikuti produk terbaru, lunas di transaction yang sama
/// dengan penjualannya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OpenBillRepository repo;

  SaleLine baris(String id, int qty, {int harga = 10000, String? catatan}) =>
      SaleLine(
        productId: id,
        productName: id,
        qty: qty,
        priceAtSale: harga,
        notes: catatan,
      );

  Future<void> masuk({String? shiftId = 's-1'}) =>
      SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'k-1',
          username: 'sari',
          role: 'cashier',
          shiftId: shiftId,
          permissions: const ['create_transaction', 'open_close_shift'],
        ),
      );

  Future<void> produk(String id, String nama, int harga) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(id: Value(id), name: nama, price: harga),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = OpenBillRepository(db);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('k-1'),
            username: 'sari',
            pinHash: 'h',
            salt: 's',
            role: 'cashier',
          ),
        );
    for (final s in ['s-1', 's-2']) {
      await db
          .into(db.shifts)
          .insert(ShiftsCompanion.insert(id: Value(s), userId: 'k-1'));
    }
    await produk('latte', 'Latte', 18000);
    await produk('teh', 'Teh', 8000);
    await masuk();
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  Future<OpenBill> ambil(String id) =>
      (db.select(db.openBills)..where((b) => b.id.equals(id))).getSingle();

  group('isi bill', () {
    test('dikodekan dan dibaca kembali utuh', () {
      final json = kodekanIsiBill([
        baris('latte', 2, catatan: 'Es: Sedikit'),
        baris('teh', 1),
      ]);
      expect(bacaIsiBill(json), [
        (idProduk: 'latte', jumlah: 2, catatan: 'Es: Sedikit'),
        (idProduk: 'teh', jumlah: 1, catatan: null),
      ]);
    });

    test(
      'harga & nama mengikuti produk terbaru, produk terhapus dibuang',
      () async {
        final id = await repo.simpan(
          nama: 'Meja 1',
          baris: [baris('latte', 2), baris('teh', 1), baris('hilang', 3)],
        );
        await (db.update(
          db.products,
        )..where((p) => p.id.equals('latte'))).write(
          const ProductsCompanion(
            name: Value('Latte Besar'),
            price: Value(20000),
          ),
        );
        final isi = muatBill(await ambil(id), await db.watchProducts().first);
        expect(isi.produkHilang, 1);
        expect(isi.baris.map((b) => (b.productName, b.priceAtSale, b.qty)), [
          ('Latte Besar', 20000, 2),
          ('Teh', 8000, 1),
        ]);
        expect(isi.total, 48000);
        expect(isi.jumlahItem, 3);
      },
    );
  });

  group('nama bill', () {
    OpenBill bill(String id, String nama) => OpenBill(
      id: id,
      name: nama,
      shiftId: 's-1',
      userId: 'k-1',
      items: '[]',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      syncStatus: 'synced',
    );

    test('wajib, maksimal 40, tidak boleh kembar (tanpa beda huruf)', () {
      final ada = [bill('b-1', 'Meja 4 · Pak Budi')];
      expect(periksaNamaBill('  ', ada), 'Nama bill wajib diisi');
      expect(periksaNamaBill('x' * 41, ada), contains('maksimal 40'));
      expect(periksaNamaBill('x' * 40, ada), isNull);
      expect(
        periksaNamaBill(' meja 4 · PAK budi ', ada),
        'Nama sudah dipakai bill lain',
      );
      expect(
        periksaNamaBill('Meja 4 · Pak Budi', ada, kecualiId: 'b-1'),
        isNull,
        reason: 'memperbarui bill itu sendiri',
      );
    });
  });

  group('repository', () {
    test('simpan, perbarui, hapus — hanya bill terbuka di shift ini', () async {
      final a = await repo.simpan(nama: 'Meja 1', baris: [baris('latte', 1)]);
      await repo.simpan(nama: 'Rina', baris: [baris('teh', 2)]);
      expect(await repo.jumlahTerbuka('s-1'), 2);
      expect(await repo.jumlahTerbuka('s-2'), 0, reason: 'milik shift lain');

      await expectLater(
        repo.simpan(nama: 'meja 1', baris: [baris('teh', 1)]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'pesan',
            'Nama sudah dipakai bill lain',
          ),
        ),
      );

      await repo.simpan(
        id: a,
        nama: 'Meja 1 · Andi',
        baris: [baris('latte', 3)],
      );
      final diperbarui = await ambil(a);
      expect(diperbarui.name, 'Meja 1 · Andi');
      expect(bacaIsiBill(diperbarui.items).single.jumlah, 3);
      expect(diperbarui.syncStatus, 'pending');

      await repo.hapus(a);
      final terhapus = await ambil(a);
      expect(
        terhapus.deletedAt,
        isNotNull,
        reason: 'hapus lunak untuk sinkron',
      );
      expect(terhapus.syncStatus, 'pending');
      expect((await repo.watchTerbuka('s-1').first).map((b) => b.name), [
        'Rina',
      ]);
      expect(
        repo.simpan(id: a, nama: 'Lagi', baris: [baris('teh', 1)]),
        throwsStateError,
        reason: 'bill yang dihapus tidak bisa diperbarui',
      );
    });

    test('tanpa shift tidak bisa menyimpan', () async {
      await masuk(shiftId: null);
      expect(
        repo.simpan(nama: 'Meja 1', baris: [baris('latte', 1)]),
        throwsStateError,
      );
    });
  });

  group('bayar bill', () {
    Future<String> bayar(String trxId, {String? billId}) => db.createSale(
      transactionId: trxId,
      lines: [baris('latte', 1, harga: 18000)],
      paymentMethod: 'qris',
      orderType: 'dine_in',
      cashierUserId: 'k-1',
      shiftId: 's-1',
      kodePerangkat: 'A',
      billId: billId,
    );

    Future<Transaction?> trx(String id) => (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    test('lunas di transaction yang sama, nama bill tersalin', () async {
      final b = await repo.simpan(nama: 'Meja 4', baris: [baris('latte', 1)]);
      await bayar('t-1', billId: b);
      expect((await trx('t-1'))!.billName, 'Meja 4');
      expect((await ambil(b)).transactionId, 't-1');
      expect((await ambil(b)).syncStatus, 'pending');
      expect(await repo.jumlahTerbuka('s-1'), 0, reason: 'hilang dari daftar');

      await bayar('t-biasa');
      expect((await trx('t-biasa'))!.billName, isNull);
    });

    test(
      'bill yang sudah dibayar / dihapus ditolak, tanpa transaksi',
      () async {
        final b = await repo.simpan(nama: 'Meja 4', baris: [baris('latte', 1)]);
        await bayar('t-1', billId: b);
        await expectLater(bayar('t-2', billId: b), throwsStateError);
        expect(await trx('t-2'), isNull);

        final c = await repo.simpan(nama: 'Rina', baris: [baris('teh', 1)]);
        await repo.hapus(c);
        await expectLater(bayar('t-3', billId: c), throwsStateError);
        expect(await trx('t-3'), isNull);
      },
    );
  });

  group('keranjang', () {
    test('memuat bill, lepas saat kosong atau dikosongkan', () {
      final k = Keranjang()..tambah(idProduk: 'x', nama: 'X', harga: 1);
      k.muatBill(
        (id: 'b-1', nama: 'Meja 1'),
        [baris('latte', 2), baris('teh', 1)],
      );
      expect(k.bill?.nama, 'Meja 1');
      expect(k.baris.map((b) => b.productId), ['latte', 'teh']);

      k.hapus(0);
      expect(k.bill, isNotNull);
      k.kurangiSatu(0);
      expect(k.bill, isNull, reason: 'keranjang kosong tidak memegang bill');

      k.muatBill((id: 'b-1', nama: 'Meja 1'), [baris('latte', 1)]);
      k.kosongkan();
      expect((k.isEmpty, k.bill), (true, null));
    });
  });

  test('cari riwayat juga mencocokkan nama bill', () {
    Transaction t(String id, String? bill) => Transaction(
      id: id,
      invoiceNo: 'TRX/$id',
      createdAt: DateTime(2026, 10, 14, 10),
      total: 1000,
      paymentMethod: 'cash',
      orderType: 'dine_in',
      billName: bill,
      updatedAt: DateTime(2026, 10, 14, 10),
      syncStatus: 'synced',
    );
    final hari = kelompokkanRiwayat(
      [t('1', 'Meja 4 · Pak Budi'), t('2', null)],
      periode: null,
      metode: null,
      cari: 'budi',
    );
    expect(hari.single.isi.map((x) => x.id), ['1']);
  });

  group('sinkron', () {
    test('dikirim dengan isi berbentuk daftar; diterima apa adanya', () async {
      final b = await repo.simpan(nama: 'Meja 1', baris: [baris('latte', 2)]);
      final terkirim = <String, List<Map<String, dynamic>>>{};
      final mesin = SyncEngine(db)
        ..pengirimUntukTest = (tabel, rows) async => terkirim[tabel] = rows;
      await mesin.dorongSemua();
      final kiriman = terkirim['open_bills']!.single;
      expect(kiriman['id'], b);
      expect(kiriman['shift_id'], 's-1');
      expect(kiriman['items'], [
        {'p': 'latte', 'q': 2},
      ], reason: 'jsonb di server, bukan teks');
      expect((await ambil(b)).syncStatus, 'synced');

      await mesin.gabungkanTabel('open_bills', [
        {
          'id': 'b-hp-lain',
          'name': 'Dari HP lain',
          'shift_id': 's-1',
          'user_id': 'k-1',
          'items': [
            {'p': 'teh', 'q': 1, 'c': 'Manis: Sedikit'},
          ],
          'transaction_id': null,
          'created_at': '2026-10-14T03:00:00Z',
          'updated_at': '2026-10-14T03:00:00Z',
          'deleted_at': null,
        },
      ]);
      final lain = await ambil('b-hp-lain');
      expect(bacaIsiBill(lain.items).single.catatan, 'Manis: Sedikit');
      expect(await repo.jumlahTerbuka('s-1'), 2);
    });

    test(
      'transaksi dari server tanpa bill_name tidak menghapus nama',
      () async {
        final b = await repo.simpan(nama: 'Meja 4', baris: [baris('latte', 1)]);
        await db.createSale(
          transactionId: 't-1',
          lines: [baris('latte', 1)],
          paymentMethod: 'cash',
          cashReceived: 10000,
          orderType: 'dine_in',
          cashierUserId: 'k-1',
          shiftId: 's-1',
          kodePerangkat: 'A',
          billId: b,
        );
        final lama = (await (db.select(
          db.transactions,
        )..where((t) => t.id.equals('t-1'))).getSingle());
        final mesin = SyncEngine(db);
        await mesin.gabungkanTabel('transactions', [
          {
            'id': 't-1',
            'invoice_no': lama.invoiceNo,
            'total': 10000,
            'payment_method': 'cash',
            'cash_received': 10000,
            'change': 0,
            'cashier_user_id': 'k-1',
            'shift_id': 's-1',
            'order_type': 'dine_in',
            'created_at': lama.createdAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'deleted_at': null,
          },
        ]);
        final baru = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals('t-1'))).getSingle();
        expect(baru.billName, 'Meja 4');
      },
    );
  });

  test('migrasi v37 → v38: tabel open_bills dan kolom bill_name', () async {
    await db.close();
    final folder = Directory.systemTemp.createTempSync('uji_v38');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v37.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama
        .into(lama.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: const Value('t-lama'),
            total: 5000,
            paymentMethod: 'cash',
          ),
        );
    await lama.close();

    final mentah = sqlite3.open(jalur);
    mentah
      ..execute('DROP TABLE open_bills')
      ..execute('ALTER TABLE transactions DROP COLUMN bill_name')
      ..execute('PRAGMA user_version = 37');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    final t = await baru.select(baru.transactions).getSingle();
    expect((t.id, t.billName), ('t-lama', null));
    expect(await baru.select(baru.openBills).get(), isEmpty);
    await baru.close();
    // tearDown menutup `db` lagi — buka yang baru supaya tetap sah.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
}
