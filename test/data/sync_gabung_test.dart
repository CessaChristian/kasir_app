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
    String? serverUrut,
  }) =>
      {
        'id': id,
        'name': nama,
        'price': 5000,
        'category_id': null,
        'has_spicy_option': false,
        'image_path': gambar,
        'created_at': '2026-09-01T00:00:00+00:00',
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        // Urutan kedatangan di server. Kalau tidak disebut, dianggap tiba
        // bersamaan dengan saat diubah — cukup untuk kasus yang tidak sedang
        // menguji penandanya.
        'server_urut': serverUrut ?? updatedAt,
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

  test('baris synced TIDAK ditulis ulang oleh pecahan detik yang sama', () async {
    // ── KEPUTUSAN INI PERNAH SEBALIKNYA ──
    //
    // Dulu baris `synced` dibandingkan presisi penuh, dengan alasan "tidak ada
    // yang bisa hilang, paling-paling ditulis ulang dengan isi yang sama".
    // Alasannya benar, tapi akibatnya tidak: salinan lokal TIDAK AKAN PERNAH
    // bisa menyamai pecahan detik milik server, sehingga baris seperti ini
    // ditulis ulang di SETIAP sinkron, selamanya, dan ikut terhitung sebagai
    // "berubah".
    //
    // Selama penandanya `gt`, baris itu tersaring keluar sesudah sekali
    // tertarik jadi tidak kelihatan. Begitu penandanya memakai jeda aman,
    // pengguna melihat "2 data diperbarui" berulang padahal tidak ada yang
    // berubah — penunjuk yang berbohong, dan penunjuk yang diabaikan sama saja
    // dengan tidak ada.
    //
    // Yang ditukar: perubahan sisi-server yang mendarat di DETIK YANG SAMA
    // dengan salinan lokal tidak akan terpakai. Itu menuntut dua penulisan ke
    // baris yang sama dalam satu detik, dengan salah satunya dari SQL langsung
    // — aplikasi selalu mengirim cap waktu berpecahan nol, karena sisi
    // lokalnya memang hanya punya detik.
    await pasangProdukLokal(
      id: 'p9',
      nama: 'Lama',
      updatedAt: detik('2026-09-04T10:04:11Z'),
      syncStatus: 'synced',
    );

    final (_, berubah) = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p9',
        nama: 'Baru',
        updatedAt: '2026-09-04T10:04:11.430427+00:00',
      ),
    ]);

    expect(berubah, 0);
    expect((await ambil('p9')).name, 'Lama');
  });

  test('baris synced TETAP menerima versi server yang detiknya lebih baru',
      () async {
    // Batas keputusan di atas: begitu detiknya benar-benar berbeda, versi
    // server menang seperti biasa. Perubahan dari perangkat lain tidak boleh
    // tertinggal — itu inti sinkronisasinya.
    await pasangProdukLokal(
      id: 'p10',
      nama: 'Lama',
      updatedAt: detik('2026-09-04T10:04:11Z'),
      syncStatus: 'synced',
    );

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p10',
        nama: 'Baru',
        updatedAt: '2026-09-04T10:04:12.430427+00:00',
      ),
    ]);

    expect((await ambil('p10')).name, 'Baru');
  });

  test('kursor tarikan disimpan UTUH dengan mikrodetiknya', () async {
    // Inti Bug 1. Kursor yang tersimpan sebagai DateTime menyusut ke detik,
    // sehingga baris yang sama tertarik ulang di SETIAP sinkronisasi — dan
    // tarikan berulang itulah yang menabrak perubahan lokal yang belum
    // terkirim.
    const tiba = '2026-09-04T10:04:11.430427+00:00';

    await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p7',
        nama: 'Air Mineral',
        updatedAt: '2026-09-04T09:00:00+00:00',
        serverUrut: tiba,
      ),
    ]);

    final kursor = await (db.select(db.syncState)
          ..where((s) => s.entity.equals('products')))
        .getSingle();

    expect(kursor.lastPulledCursor, tiba,
        reason: 'penanda mengikuti URUTAN KEDATANGAN (`server_urut`), bukan '
            '`updated_at`. Memakai `updated_at` membuat baris yang tiba '
            'terlambat terlewat permanen; mikrodetiknya juga wajib utuh, '
            'kalau terpangkas baris ini tertarik ulang selamanya');
  });
  test('produk terhapus yang belum pernah ada di sini TIDAK disimpan', () async {
    // HP yang dipasang dari nol tidak perlu menyimpan sampah. Tidak ada yang
    // bisa merujuknya: item struk tidak terikat ke produk (v24).
    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p-sampah',
        nama: 'Teh lama',
        updatedAt: '2026-08-01T10:00:00+00:00',
        deletedAt: '2026-08-01T10:00:00+00:00',
      ),
    ]);

    expect(hasil, (1, 0), reason: 'dibaca, tapi bukan perubahan');
    expect(await db.select(db.products).get(), isEmpty);

    final penanda = await (db.select(db.syncState)
          ..where((s) => s.entity.equals('products')))
        .getSingle();
    expect(penanda.lastPulledCursor, '2026-08-01T10:00:00+00:00',
        reason: 'penanda tetap maju walau barisnya dilewati — kalau tidak, '
            'baris yang sama tertarik ulang di setiap sinkron');
  });

  test('kategori terhapus yang belum pernah ada di sini TIDAK disimpan',
      () async {
    // Aman karena server tidak lagi menyimpan produk aktif yang menunjuk
    // kategori terhapus (supabase/kategori_terhapus.sql).
    await mesin.gabungkanTabel('categories', [
      {
        'id': 'k-sampah',
        'name': 'Minuman lama',
        'icon_codepoint': null,
        'created_at': '2026-08-01T10:00:00+00:00',
        'updated_at': '2026-08-01T10:00:00+00:00',
        'deleted_at': '2026-08-01T10:00:00+00:00',
        'server_urut': '2026-08-01T10:00:00+00:00',
      },
    ]);
    expect(await db.select(db.categories).get(), isEmpty);
  });

  test('transaksi yang DIBATALKAN tetap disimpan walau belum pernah ada',
      () async {
    // Pembatalan adalah catatan untuk owner, bukan sampah — HP yang dipasang
    // dari nol wajib ikut menyimpannya. Tidak dihitung "diperbarui" karena
    // tidak mengubah total apa pun.
    final hasil = await mesin.gabungkanTabel('transactions', [
      {
        'id': 't-batal',
        'invoice_no': 'TRX/01',
        'total': 20000,
        'payment_method': 'cash',
        'cash_received': 20000,
        'change': 0,
        'cashier_user_id': null,
        'shift_id': null,
        'order_type': 'dine_in',
        'created_at': '2026-08-01T10:00:00+00:00',
        'updated_at': '2026-08-01T11:00:00+00:00',
        'deleted_at': '2026-08-01T11:00:00+00:00',
        'cancelled_by_user_id': null,
        'cancel_reason': 'Salah input',
        'server_urut': '2026-08-01T11:00:00+00:00',
      },
    ]);
    expect(hasil, (1, 0));
    final t = await db.select(db.transactions).getSingle();
    expect(t.cancelReason, 'Salah input');
  });

  test('penghapusan baris yang ADA di sini tetap dihitung berubah', () async {
    await pasangProdukLokal(
      id: 'p-ada',
      nama: 'Es Jeruk',
      updatedAt: detik('2026-09-04T09:00:00Z'),
      syncStatus: 'synced',
    );

    final hasil = await mesin.gabungkanTabel('products', [
      barisServer(
        id: 'p-ada',
        nama: 'Es Jeruk',
        updatedAt: '2026-09-04T11:00:00+00:00',
        deletedAt: '2026-09-04T11:00:00+00:00',
      ),
    ]);

    expect(hasil, (1, 1),
        reason: 'produk ini hilang dari layar — itu perubahan nyata');
  });
}
