import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci aturan menang-kalah saat menarik data dari server.
///
/// ── BUG YANG DIKUNCI DI SINI ──
///
/// Dulu baris dari server ditulis begitu saja lewat `insertOnConflictUpdate`
/// tanpa membandingkan apa pun, sekaligus menyetel `sync_status = 'synced'`.
/// Untuk baris yang punya perubahan lokal belum terkirim, akibatnya fatal dan
/// senyap:
///
/// ```
/// 1. pengguna menambah gambar   -> lokal: image_path terisi, 'pending'
/// 2. pengguna menyegarkan       -> TARIK dulu, baru DORONG
/// 3. tarikan menimpa baris itu  -> image_path kembali NULL, jadi 'synced'
/// 4. giliran dorong             -> tidak ada lagi yang 'pending'
/// ```
///
/// Gambarnya hilang dari layar DAN tidak pernah sampai ke server; filenya
/// tertinggal di disk tanpa ada yang menunjuknya. Ditemukan di perangkat
/// sungguhan: produk "Air Mineral" berakhir `image_path=NULL, sync=synced`
/// dengan satu file webp yatim di folder produk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine mesin;

  /// Waktu lokal selalu beresolusi DETIK — itu yang disimpan drift.
  DateTime detik(String iso) {
    final t = DateTime.parse(iso);
    return DateTime.fromMillisecondsSinceEpoch(
        (t.millisecondsSinceEpoch ~/ 1000) * 1000);
  }

  Map<String, dynamic> barisServer({
    required String id,
    required String nama,
    String? gambar,
    required String updatedAt,
    String? deletedAt,
  }) =>
      {
        'id': id,
        'name': nama,
        'price': 5000,
        'barcode': null,
        'category_id': null,
        'has_spicy_option': false,
        'image_path': gambar,
        'created_at': '2026-09-01T00:00:00+00:00',
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  Future<void> pasangProdukLokal({
    required String id,
    required String nama,
    String? gambar,
    required DateTime updatedAt,
    required String syncStatus,
  }) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: nama,
            price: 5000,
            imagePath: Value(gambar),
            updatedAt: Value(updatedAt),
            syncStatus: Value(syncStatus),
          ));

  Future<Product> ambil(String id) =>
      (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mesin = SyncEngine(db);
  });

  tearDown(() => db.close());

  test('baris pending yang LEBIH BARU tidak boleh ditimpa tarikan', () async {
    // Persis kejadian "Air Mineral": server belum punya gambarnya, pengguna
    // baru saja menambahkannya di sini dan belum sempat terkirim.
    await pasangProdukLokal(
      id: 'p1',
      nama: 'Air Mineral',
      gambar: 'products/foto-baru.webp',
      updatedAt: detik('2026-09-04T10:30:00Z'),
      syncStatus: 'pending',
    );

    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p1',
        nama: 'Air Mineral',
        gambar: null,
        updatedAt: '2026-09-04T10:04:11.430427+00:00',
      ),
    ]);

    final p = await ambil('p1');
    expect(p.imagePath, 'products/foto-baru.webp',
        reason: 'gambar yang baru ditambahkan tidak boleh hilang');
    expect(p.syncStatus, 'pending',
        reason: 'harus tetap mengantre kirim, kalau tidak selamanya '
            'tertinggal di perangkat ini saja');
    expect(hasil.$2, 0, reason: 'tidak ada yang benar-benar berubah');
  });

  test('penghapusan dari server yang LEBIH BARU tetap menang', () async {
    // Sisi sebaliknya: aturan tidak boleh jadi "pending selalu menang",
    // karena produk yang dihapus pemilik harus benar-benar hilang di HP kasir.
    await pasangProdukLokal(
      id: 'p2',
      nama: 'Es Teh',
      updatedAt: detik('2026-09-04T09:00:00Z'),
      syncStatus: 'pending',
    );

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p2',
        nama: 'Es Teh',
        updatedAt: '2026-09-04T11:00:00+00:00',
        deletedAt: '2026-09-04T11:00:00+00:00',
      ),
    ]);

    final p = await ambil('p2');
    expect(p.deletedAt, isNotNull,
        reason: 'penghapusan yang lebih baru harus menang atas edit lokal');
  });

  test('seri di detik yang sama dimenangkan yang lokal', () async {
    // `updated_at` lokal beresolusi detik, jadi urutan di dalam satu detik
    // tidak bisa dibedakan. Kalau ragu, yang belum terkirim diselamatkan —
    // ia hanya ada di perangkat ini.
    await pasangProdukLokal(
      id: 'p3',
      nama: 'Kopi',
      gambar: 'products/lokal.webp',
      updatedAt: detik('2026-09-04T10:00:00Z'),
      syncStatus: 'pending',
    );

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p3',
        nama: 'Kopi',
        gambar: null,
        updatedAt: '2026-09-04T10:00:00+00:00',
      ),
    ]);

    final p = await ambil('p3');
    expect(p.imagePath, 'products/lokal.webp');
    expect(p.syncStatus, 'pending');
  });

  test('baris server yang lebih baru tetap masuk ke baris synced', () async {
    // Jangan sampai perbaikan ini malah memblokir sinkronisasi normal.
    await pasangProdukLokal(
      id: 'p4',
      nama: 'Roti',
      updatedAt: detik('2026-09-04T08:00:00Z'),
      syncStatus: 'synced',
    );

    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p4',
        nama: 'Roti Bakar',
        updatedAt: '2026-09-04T12:00:00+00:00',
      ),
    ]);

    expect((await ambil('p4')).name, 'Roti Bakar');
    expect(hasil.$2, 1, reason: 'ini perubahan nyata, layak dihitung');
  });

  test('baris yang isinya sudah sama tidak dihitung sebagai perubahan',
      () async {
    // Keluhan pengguna: popup melaporkan "N data diperbarui" padahal daftarnya
    // tidak berubah sama sekali. Yang dilaporkan harus perubahan NYATA.
    await pasangProdukLokal(
      id: 'p5',
      nama: 'Teh Manis',
      updatedAt: detik('2026-09-04T10:00:00Z'),
      syncStatus: 'synced',
    );

    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p5',
        nama: 'Teh Manis',
        updatedAt: '2026-09-04T10:00:00+00:00',
      ),
    ]);

    expect(hasil.$1, 1, reason: 'satu baris memang diterima dari server');
    expect(hasil.$2, 0, reason: 'tapi tidak ada yang berubah — jangan diklaim');
  });

  test('baris yang belum ada di sini selalu masuk', () async {
    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p6',
        nama: 'Produk Baru',
        updatedAt: '2026-09-04T10:00:00+00:00',
      ),
    ]);

    expect((await ambil('p6')).name, 'Produk Baru');
    expect(hasil.$2, 1);
  });

  test('edit pending di DETIK YANG SAMA dengan cap server tidak hilang',
      () async {
    // Lubang halus yang sempat tersisa setelah perbaikan pertama.
    //
    // Waktu lokal cuma beresolusi detik, jadi salinan lokal dari baris server
    // kehilangan pecahannya:
    //
    //   server : 10:04:11.430427
    //   lokal  : 10:04:11.000000   <- baris yang SAMA, pecahan terbuang
    //
    // Kalau dibandingkan penuh, versi server selamanya terlihat lebih baru
    // daripada salinannya sendiri — dan edit pengguna pada detik itu ikut
    // tertimpa, padahal kenyataannya terjadi belakangan.
    await pasangProdukLokal(
      id: 'p8',
      nama: 'Air Mineral',
      gambar: 'products/foto-baru.webp',
      updatedAt: detik('2026-09-04T10:04:11Z'),
      syncStatus: 'pending',
    );

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p8',
        nama: 'Air Mineral',
        gambar: null,
        updatedAt: '2026-09-04T10:04:11.430427+00:00',
      ),
    ]);

    final p = await ambil('p8');
    expect(p.imagePath, 'products/foto-baru.webp',
        reason: 'pecahan detik milik server tidak boleh mengalahkan edit '
            'lokal yang cap waktunya memang tidak bisa sepresisi itu');
    expect(p.syncStatus, 'pending');
  });

  test('baris synced tetap menerima versi server yang lebih baru sepersekian '
      'detik', () async {
    // Sisi sebaliknya: untuk baris yang TIDAK punya perubahan lokal, tidak ada
    // yang bisa hilang — jadi perbandingannya tetap presisi penuh supaya
    // perubahan dari perangkat lain tidak tertinggal.
    await pasangProdukLokal(
      id: 'p9',
      nama: 'Lama',
      updatedAt: detik('2026-09-04T10:04:11Z'),
      syncStatus: 'synced',
    );

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p9',
        nama: 'Baru',
        updatedAt: '2026-09-04T10:04:11.430427+00:00',
      ),
    ]);

    expect((await ambil('p9')).name, 'Baru');
  });

  test('kursor tarikan disimpan UTUH dengan mikrodetiknya', () async {
    // Inti Bug 1. Kursor yang tersimpan sebagai DateTime menyusut ke detik,
    // sehingga `updated_at > kursor` terus-menerus mengambil ulang baris yang
    // sama di SETIAP sinkronisasi — dan tarikan berulang itulah yang
    // menabrak perubahan lokal yang belum terkirim.
    const waktu = '2026-09-04T10:04:11.430427+00:00';

    await mesin.gabungkanTabel('products', [
      barisServer(id: 'p7', nama: 'Air Mineral', updatedAt: waktu),
    ]);

    final kursor = await (db.select(db.syncState)
          ..where((s) => s.entity.equals('products')))
        .getSingle();

    expect(kursor.lastPulledCursor, waktu,
        reason: 'mikrodetik WAJIB utuh; kalau terpangkas jadi 10:04:11, '
            'baris ini akan tertarik ulang selamanya');
  });
}
