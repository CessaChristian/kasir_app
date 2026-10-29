import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci ketahanan pengiriman terhadap kegagalan sebagian.
///
/// ── YANG DIKUNCI DI SINI ──
///
/// Dulu seluruh sinkronisasi ada di dalam SATU `try`. Satu kegagalan di mana
/// pun membatalkan semua sisanya: satu tabel ditolak, tabel sesudahnya tidak
/// pernah dicoba; dan satu baris rusak menjatuhkan 99 baris sehat di potongan
/// yang sama, membuat tabelnya macet setiap sync selamanya.
///
/// Bukan dugaan — sudah terjadi di project ini: 78 baris berformat ID lama
/// ditolak dengan `invalid input syntax for type uuid`, dan pengiriman
/// tabelnya berhenti total.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> pasangProduk(String nama) async {
    final id = 'p-$nama';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(id),
          name: nama,
          price: 5000,
          syncStatus: const Value('pending'),
        ));
    return id;
  }

  Future<void> pasangKategori(String nama) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(
            id: Value('k-$nama'),
            name: nama,
            syncStatus: const Value('pending'),
          ));

  Future<String> status(String id) async {
    final r = await (db.select(db.products)..where((p) => p.id.equals(id)))
        .getSingle();
    return r.syncStatus;
  }

  test('satu baris beracun tidak menjatuhkan baris sehat setimpuk', () async {
    final sehat1 = await pasangProduk('Kopi');
    final racun = await pasangProduk('BERACUN');
    final sehat2 = await pasangProduk('Teh');

    final mesin = SyncEngine(db)
      ..pengirimUntukTest = (tabel, baris) async {
        if (baris.any((b) => b['name'] == 'BERACUN')) {
          throw Exception('invalid input syntax for type uuid');
        }
      };

    final (terkirim, gagal) = await mesin.dorongSemua();

    expect(await status(sehat1), 'synced',
        reason: 'baris sehat WAJIB lolos walau setimpuk dengan yang beracun');
    expect(await status(sehat2), 'synced');
    expect(await status(racun), 'pending',
        reason: 'yang beracun tetap mengantre supaya dicoba lagi nanti — '
            'menyerah diam-diam pada data lebih berbahaya daripada berisik');
    expect(terkirim, 2);
    expect(gagal, hasLength(1));
    expect(gagal.first, contains('products'));
    expect(mesin.ditolak, 1, reason: 'QA S10: dilaporkan ke owner');
  });

  test('QA K10: jumlahTertunda menghitung yang belum terkirim di semua tabel',
      () async {
    await pasangKategori('Minuman');
    await pasangProduk('Kopi');
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('p-sudah'),
          name: 'Sudah',
          price: 1,
          syncStatus: const Value('synced'),
        ));
    expect(await db.jumlahTertunda(), 2);
  });

  test('satu tabel gagal tidak menghentikan tabel lain', () async {
    await pasangKategori('Minuman');
    final produk = await pasangProduk('Kopi');

    final mesin = SyncEngine(db)
      ..pengirimUntukTest = (tabel, baris) async {
        if (tabel == 'categories') throw Exception('server menolak');
      };

    final (terkirim, gagal) = await mesin.dorongSemua();

    expect(await status(produk), 'synced',
        reason: 'tidak ada alasan produk ikut mati karena kategori bermasalah');
    expect(terkirim, 1);
    expect(gagal, hasLength(1));
    expect(gagal.first, contains('categories'));
  });

  test('semua lolos -> tidak ada yang dilaporkan gagal', () async {
    await pasangProduk('Kopi');
    await pasangKategori('Minuman');

    final mesin = SyncEngine(db)..pengirimUntukTest = (_, _) async {};

    final (terkirim, gagal) = await mesin.dorongSemua();

    expect(terkirim, 2);
    expect(gagal, isEmpty);
  });

  test('baris yang gagal TIDAK ditandai terkirim', () async {
    final id = await pasangProduk('Gagal');

    final mesin = SyncEngine(db)
      ..pengirimUntukTest = (_, _) async => throw Exception('putus');

    await mesin.dorongSemua();

    expect(await status(id), 'pending',
        reason: 'menandai terkirim padahal ditolak = data hilang diam-diam');
  });

  group('perubahan yang terjadi SELAGI dikirim', () {
    // Pengiriman makan waktu 1–3 detik. Baris yang diubah kasir di sela itu
    // dulu tetap dicap "terkirim" — padahal yang sampai ke server versi
    // lamanya — lalu tidak pernah dikirim lagi.

    test('transaksi dibatalkan di tengah pengiriman: pembatalannya tetap '
        'terkirim', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: const Value('tx-es-teh'),
            total: 5000,
            paymentMethod: 'cash',
            syncStatus: const Value('pending'),
          ));
      final kiriman = <Map<String, dynamic>>[];
      final mesin = SyncEngine(db)
        ..pengirimUntukTest = (tabel, baris) async {
          if (tabel != 'transactions') return;
          kiriman.addAll(baris);
          // Kasir membatalkan Es Teh tepat saat kurir di jalan.
          if (kiriman.length == 1) {
            await (db.update(db.transactions)
                  ..where((t) => t.id.equals('tx-es-teh')))
                .write(TransactionsCompanion(
              deletedAt: Value(DateTime.now()),
              cancelReason: const Value('Salah input'),
              syncStatus: const Value('pending'),
            ));
          }
        };

      await mesin.dorongSemua();
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx-es-teh')))
          .getSingle();
      expect(tx.syncStatus, 'pending',
          reason: 'server baru menerima versi SAH; pembatalan belum sampai');
      expect(kiriman.single['deleted_at'], isNull);

      // Putaran berikutnya membawa pembatalannya, lalu baru dicap terkirim.
      await mesin.dorongSemua();
      expect(kiriman, hasLength(2));
      expect(kiriman.last['deleted_at'], isNotNull);
      expect(kiriman.last['cancel_reason'], 'Salah input');
      final akhir = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx-es-teh')))
          .getSingle();
      expect(akhir.syncStatus, 'synced');
    });

    test('baris lain di potongan yang sama tetap dicap terkirim', () async {
      final kopi = await pasangProduk('Kopi');
      final teh = await pasangProduk('Teh');
      final mesin = SyncEngine(db)
        ..pengirimUntukTest = (tabel, baris) async {
          if (tabel != 'products') return;
          await (db.update(db.products)..where((p) => p.id.equals(teh)))
              .write(const ProductsCompanion(
            price: Value(7000),
            syncStatus: Value('pending'),
          ));
        };
      final (terkirim, gagal) = await mesin.dorongSemua();
      expect(await status(kopi), 'synced');
      expect(await status(teh), 'pending', reason: 'harga 7000 belum terkirim');
      expect(terkirim, 2, reason: 'keduanya memang sampai ke server');
      expect(gagal, isEmpty);
    });
  });

  test('HasilSync membedakan gagal total dari berhasil sebagian', () {
    const total = HasilSync(error: 'putus');
    const sebagian = HasilSync(didorong: 5, error: 'satu tabel gagal');

    expect(total.sebagian, isFalse);
    expect(sebagian.sebagian, isTrue,
        reason: 'menyebutnya "gagal" saja keliru — data yang lolos memang '
            'sudah tersimpan; menyebutnya berhasil lebih keliru lagi');
    expect(sebagian.toString(), contains('SEBAGIAN'));
  });
}
