import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu baris dari server yang DITOLAK database HP (aturan isian yang belum
/// mengenal nilai baru, induk yang belum ada) tidak boleh lagi menghentikan
/// seluruh tarikan.
///
/// Dulu: penandanya tidak maju, tabel sesudahnya tidak pernah ditarik, dan
/// setiap lima menit semua baris sejak hari itu diunduh ulang — tanpa ada
/// yang tahu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;

  /// Isi server per tabel, urut kedatangan.
  late Map<String, List<Map<String, dynamic>>> server;
  late List<String> diminta;

  final t0 = DateTime.utc(2026, 10, 22, 8);
  String iso(int menit) =>
      t0.add(Duration(minutes: menit)).toIso8601String();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncEngine.lupakanCobaLagi();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    server = {};
    diminta = [];
    mesin = SyncEngine(db)
      ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
        diminta.add(tabel);
        final semua = server[tabel] ?? const [];
        final mulai = setelah == null
            ? 0
            : semua.indexWhere((r) => r['id'] == setelah.id) + 1;
        return semua
            .skip(mulai)
            .where((r) =>
                setelah != null ||
                sejak == null ||
                !DateTime.parse(r[kolom] as String)
                    .isBefore(DateTime.parse(sejak)))
            .take(batas)
            .toList();
      }
      ..pengambilIdUntukTest = (tabel, ids) async => [
            for (final r in server[tabel] ?? const <Map<String, dynamic>>[])
              if (ids.contains(r['id'])) r,
          ];

    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value('k-1'),
          username: 'sari',
          pinHash: 'h',
          salt: 's',
          role: 'cashier',
        ));
    await db.into(db.shifts).insert(
        ShiftsCompanion.insert(id: const Value('s-1'), userId: 'k-1'));
  });

  tearDown(() => db.close());

  Map<String, dynamic> pengeluaran(String id, int menit,
          {String kategori = 'bahan_baku'}) =>
      {
        'id': id,
        'shift_id': 's-1',
        'user_id': 'k-1',
        'description': id,
        'amount': 5000,
        'category': kategori,
        'qty': 1,
        'created_at': iso(menit),
        'updated_at': iso(menit),
        'deleted_at': null,
        'server_urut': iso(menit),
      };

  Map<String, dynamic> bill(String id, int menit) => {
        'id': id,
        'name': id,
        'shift_id': 's-1',
        'user_id': 'k-1',
        'items': [
          {'p': 'x', 'q': 1},
        ],
        'transaction_id': null,
        'created_at': iso(menit),
        'updated_at': iso(menit),
        'deleted_at': null,
        'server_urut': iso(menit),
      };

  Future<List<String>> idPengeluaran() async =>
      [for (final e in await db.select(db.expenses).get()) e.id]..sort();

  Future<List<BarisTertahanEntry>> tertahan() =>
      db.select(db.barisTertahan).get();

  Future<String?> penanda(String tabel) async =>
      (await (db.select(db.syncState)..where((s) => s.entity.equals(tabel)))
              .getSingleOrNull())
          ?.lastPulledCursor;

  test('kategori yang belum dikenal HP ini: barisnya disisihkan, sisanya '
      'tetap masuk, tabel sesudahnya tetap ditarik', () async {
    server['expenses'] = [
      pengeluaran('es-batu', 1),
      // Kategori dari APK yang lebih baru — aturan isian HP ini menolaknya.
      pengeluaran('gaji-sari', 2, kategori: 'gaji'),
      pengeluaran('gas', 3),
    ];
    server['open_bills'] = [bill('meja-1', 4)];

    await mesin.tarikSemua();

    expect(await idPengeluaran(), ['es-batu', 'gas']);
    final t = await tertahan();
    expect(t.map((x) => (x.entity, x.rowId)), [('expenses', 'gaji-sari')]);
    expect(t.single.alasan, contains('CHECK'));
    expect(await penanda('expenses'), iso(3),
        reason: 'penanda maju melewati baris yang ditahan');
    expect((await db.select(db.openBills).get()).single.id, 'meja-1',
        reason: 'tabel sesudah expenses tetap ditarik');
  });

  test('baris tertahan dicoba lagi di putaran berikutnya', () async {
    server['expenses'] = [
      pengeluaran('es-batu', 1),
      pengeluaran('gaji-sari', 2, kategori: 'gaji'),
    ];
    await mesin.tarikSemua();
    expect(await tertahan(), hasLength(1));

    SyncEngine.lupakanCobaLagi(); // sejam kemudian
    var diambilUlang = <String>[];
    mesin.pengambilIdUntukTest = (tabel, ids) async {
      diambilUlang = ids;
      // Seolah servernya sudah membetulkan barisnya (atau aplikasi sudah
      // diperbarui dan mengenal kategorinya).
      return [
        if (ids.contains('gaji-sari')) pengeluaran('gaji-sari', 2),
      ];
    };
    await mesin.tarikSemua();

    expect(diambilUlang, ['gaji-sari']);
    expect(await idPengeluaran(), ['es-batu', 'gaji-sari']);
    expect(await tertahan(), isEmpty, reason: 'sudah masuk: dilepas');
  });

  test('baris tertahan yang sudah tidak ada di server dilepas', () async {
    server['expenses'] = [pengeluaran('gaji-sari', 2, kategori: 'gaji')];
    await mesin.tarikSemua();
    expect(await tertahan(), hasLength(1));

    server['expenses'] = [];
    SyncEngine.lupakanCobaLagi(); // sejam kemudian
    await mesin.tarikSemua();
    expect(await tertahan(), isEmpty);
  });

  test('dicoba ulang paling sering sekali per jam', () async {
    server['expenses'] = [pengeluaran('gaji-sari', 2, kategori: 'gaji')];
    var ditanya = 0;
    final asli = mesin.pengambilIdUntukTest!;
    mesin.pengambilIdUntukTest = (tabel, ids) async {
      ditanya++;
      return asli(tabel, ids);
    };
    await mesin.tarikSemua(); // baris baru tertahan
    await mesin.tarikSemua(); // coba ulang pertama
    await mesin.tarikSemua(); // masih dalam sejam: tidak ditanya
    await mesin.tarikSemua();
    expect(ditanya, 1);
    expect(SyncEngine.jedaCobaLagi, const Duration(hours: 1));

    SyncEngine.lupakanCobaLagi(); // aplikasi dibuka ulang / sejam kemudian
    await mesin.tarikSemua();
    expect(ditanya, 2);
  });

  test('salinan lama di HP ditandai terhapus kalau barisnya sudah dibuang '
      'server', () async {
    // HP punya produk versi lama. Versi barunya di server menunjuk kategori
    // yang belum ada di sini, jadi tertahan.
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value('kopi'),
          name: 'Kopi',
          price: 10000,
          updatedAt: Value(DateTime.utc(2026, 1, 1)),
          syncStatus: const Value('synced'),
        ));
    server['products'] = [
      {
        'id': 'kopi',
        'name': 'Kopi',
        'price': 12000,
        'category_id': 'kategori-yang-belum-ada',
        'created_at': iso(1),
        'updated_at': iso(1),
        'deleted_at': null,
        'server_urut': iso(1),
      },
    ];
    await mesin.tarikSemua();
    expect((await tertahan()).single.rowId, 'kopi');

    // Produknya lalu dihapus dan sudah dibuang server.
    server['products'] = [];
    SyncEngine.lupakanCobaLagi();
    await mesin.tarikSemua();

    final kopi = await (db.select(db.products)
          ..where((p) => p.id.equals('kopi')))
        .getSingle();
    expect(kopi.deletedAt, isNotNull, reason: 'tidak tampil lagi di Kasir');
    expect(kopi.syncStatus, 'synced', reason: 'tidak dikirim balik ke server');
    expect(await tertahan(), isEmpty);
  });

  test('yang masih ditolak tetap tertahan, tidak menggandakan catatan',
      () async {
    server['expenses'] = [pengeluaran('gaji-sari', 2, kategori: 'gaji')];
    await mesin.tarikSemua();
    await mesin.tarikSemua();
    await mesin.tarikSemua();
    expect(await tertahan(), hasLength(1));
    expect(await db.jumlahTertahan(), 1);
  });

  test('penanda disimpan per halaman: putus di halaman kedua tidak '
      'mengulang dari nol', () async {
    server['expenses'] = [
      for (var i = 0; i < SyncEngine.ukuranHalaman + 5; i++)
        pengeluaran('e${i.toString().padLeft(4, '0')}', i),
    ];
    final asli = mesin.penarikUntukTest!;
    var halaman = 0;
    mesin.penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
      if (tabel == 'expenses' && ++halaman == 2) {
        throw Exception('koneksi putus');
      }
      return asli(tabel, kolom, sejak, setelah, batas);
    };

    await expectLater(mesin.tarikSemua(), throwsException);
    expect(await idPengeluaran(), hasLength(SyncEngine.ukuranHalaman),
        reason: 'halaman pertama sudah tersimpan');
    expect(await penanda('expenses'), iso(SyncEngine.ukuranHalaman - 1));
  });
}
