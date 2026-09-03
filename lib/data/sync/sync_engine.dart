import 'package:drift/drift.dart';

import '../app_database.dart';
import '../supabase/supabase_service.dart';

/// Hasil satu putaran sinkronisasi, untuk ditampilkan atau dicatat.
class HasilSync {
  final int ditarik;
  final int didorong;
  final String? error;

  const HasilSync({this.ditarik = 0, this.didorong = 0, this.error});

  bool get berhasil => error == null;

  @override
  String toString() => berhasil
      ? 'tarik $ditarik, dorong $didorong'
      : 'GAGAL: $error';
}

/// Menyinkronkan database lokal dengan Supabase.
///
/// ── KENAPA TIDAK ADA TABEL OUTBOX TERPISAH ──
///
/// Kolom `sync_status` yang sudah ada DI SETIAP BARIS sudah berperan sebagai
/// antrean: baris bernilai 'pending' adalah baris yang belum terkirim.
///
/// Alternatifnya adalah tabel antrean yang mencatat setiap operasi. Itu lebih
/// setia pada urutan kejadian, tapi tidak berguna di sini: penyelesaian
/// konflik kita memakai "yang terbaru menang". Kalau satu baris diubah tiga
/// kali saat offline, mengirim keadaan TERAKHIRNYA sekali menghasilkan yang
/// sama persis dengan memutar ulang tiga operasi — dengan sepertiga lalu
/// lintas dan tanpa tabel tambahan yang harus dijaga konsistensinya.
///
/// ── KENAPA PENGHAPUSAN TETAP TERKIRIM ──
///
/// Karena semua penghapusan bersifat lunak (`deleted_at` diisi, barisnya
/// tetap ada), penghapusan terkirim sebagai perubahan biasa. Baris yang
/// benar-benar lenyap tidak bisa diberitahukan ke perangkat lain — server
/// hanya melihat ketiadaan, dan ketiadaan tidak bisa dikirim.
class SyncEngine {
  final AppDatabase _db;

  SyncEngine(this._db);

  SupabaseService get _supabase => SupabaseService.instance;

  /// Tarik dulu, baru dorong.
  ///
  /// Urutannya disengaja: kalau mendorong lebih dulu, perubahan lokal bisa
  /// menimpa perubahan server yang belum sempat dilihat — padahal mungkin
  /// server yang lebih baru.
  Future<HasilSync> jalankan() async {
    if (!_supabase.online) {
      return const HasilSync(error: 'offline atau perangkat belum didaftarkan');
    }
    try {
      final ditarik = await _tarikSemua();
      final didorong = await _dorongSemua();
      return HasilSync(ditarik: ditarik, didorong: didorong);
    } catch (e) {
      return HasilSync(error: e.toString());
    }
  }

  // ------------------------------------------------------------------
  // TARIK
  // ------------------------------------------------------------------

  Future<int> _tarikSemua() async {
    var total = 0;
    // Induk dulu: produk mengacu ke kategori, jadi kategorinya harus sudah
    // ada sebelum produknya masuk.
    total += await _tarik('categories', _simpanKategori);
    total += await _tarik('products', _simpanProduk);
    return total;
  }

  /// Ambil baris yang berubah setelah penarikan terakhir.
  Future<int> _tarik(
    String entitas,
    Future<void> Function(Map<String, dynamic>) simpan,
  ) async {
    final sejak = await _waktuTarikTerakhir(entitas);

    var query = _supabase.client!.from(entitas).select();
    if (sejak != null) {
      query = query.gt('updated_at', sejak.toUtc().toIso8601String());
    }
    final baris = await query.order('updated_at');
    if (baris.isEmpty) return 0;

    DateTime? paling;
    for (final r in baris) {
      await simpan(r);
      final u = DateTime.parse(r['updated_at'] as String);
      if (paling == null || u.isAfter(paling)) paling = u;
    }
    await _catatWaktuTarik(entitas, paling!);
    return baris.length;
  }

  Future<void> _simpanKategori(Map<String, dynamic> r) async {
    await _db.into(_db.categories).insertOnConflictUpdate(
          CategoriesCompanion(
            id: Value(r['id'] as String),
            name: Value(r['name'] as String),
            iconCodepoint: Value(r['icon_codepoint'] as int?),
            createdAt: Value(_waktu(r['created_at'])!),
            updatedAt: Value(_waktu(r['updated_at'])!),
            deletedAt: Value(_waktu(r['deleted_at'])),
            // Baris ini datang DARI server, jadi menurut definisi sudah
            // tersinkron. Menandainya 'pending' akan membuatnya terkirim
            // balik tanpa alasan.
            syncStatus: const Value('synced'),
          ),
        );
  }

  Future<void> _simpanProduk(Map<String, dynamic> r) async {
    await _db.into(_db.products).insertOnConflictUpdate(
          ProductsCompanion(
            id: Value(r['id'] as String),
            name: Value(r['name'] as String),
            price: Value((r['price'] as num).toInt()),
            barcode: Value(r['barcode'] as String?),
            categoryId: Value(r['category_id'] as String?),
            trackStock: Value(r['track_stock'] as bool),
            stock: Value(r['stock'] as int?),
            hasSpicyOption: Value(r['has_spicy_option'] as bool),
            imagePath: Value(r['image_path'] as String?),
            createdAt: Value(_waktu(r['created_at'])!),
            updatedAt: Value(_waktu(r['updated_at'])!),
            deletedAt: Value(_waktu(r['deleted_at'])),
            syncStatus: const Value('synced'),
          ),
        );
  }

  // ------------------------------------------------------------------
  // DORONG
  // ------------------------------------------------------------------

  Future<int> _dorongSemua() async {
    var total = 0;
    total += await _dorongKategori();
    total += await _dorongProduk();
    return total;
  }

  Future<int> _dorongKategori() async {
    final tertunda = await (_db.select(_db.categories)
          ..where((c) => c.syncStatus.equals('pending')))
        .get();
    if (tertunda.isEmpty) return 0;

    await _supabase.client!.from('categories').upsert([
      for (final c in tertunda)
        {
          'id': c.id,
          'name': c.name,
          'icon_codepoint': c.iconCodepoint,
          'created_at': c.createdAt.toUtc().toIso8601String(),
          'updated_at': c.updatedAt.toUtc().toIso8601String(),
          'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
        }
    ]);

    await _tandaiTerkirim(_db.categories, tertunda.map((c) => c.id).toList());
    return tertunda.length;
  }

  Future<int> _dorongProduk() async {
    final tertunda = await (_db.select(_db.products)
          ..where((p) => p.syncStatus.equals('pending')))
        .get();
    if (tertunda.isEmpty) return 0;

    await _supabase.client!.from('products').upsert([
      for (final p in tertunda)
        {
          'id': p.id,
          'name': p.name,
          'price': p.price,
          'barcode': p.barcode,
          'category_id': p.categoryId,
          'track_stock': p.trackStock,
          'stock': p.stock,
          'has_spicy_option': p.hasSpicyOption,
          'image_path': p.imagePath,
          'created_at': p.createdAt.toUtc().toIso8601String(),
          'updated_at': p.updatedAt.toUtc().toIso8601String(),
          'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
        }
    ]);

    await _tandaiTerkirim(_db.products, tertunda.map((p) => p.id).toList());
    return tertunda.length;
  }

  /// Tandai baris sudah terkirim.
  ///
  /// `updated_at` SENGAJA tidak ikut diubah. Kolom itu menyatakan kapan
  /// datanya berubah menurut pengguna, bukan kapan ia terkirim — dan nilainya
  /// dipakai untuk memutuskan versi mana yang menang. Menyentuhnya di sini
  /// akan membuat baris ini selalu "menang" atas perubahan perangkat lain.
  Future<void> _tandaiTerkirim(TableInfo tabel, List<String> ids) async {
    await _db.customUpdate(
      "UPDATE ${tabel.actualTableName} SET sync_status = 'synced' "
      "WHERE id IN (${List.filled(ids.length, '?').join(',')})",
      variables: [for (final id in ids) Variable.withString(id)],
      updates: {tabel},
    );
  }

  // ------------------------------------------------------------------
  // Penanda waktu
  // ------------------------------------------------------------------

  Future<DateTime?> _waktuTarikTerakhir(String entitas) async {
    final baris = await (_db.select(_db.syncState)
          ..where((s) => s.entity.equals(entitas)))
        .getSingleOrNull();
    return baris?.lastPulledAt;
  }

  Future<void> _catatWaktuTarik(String entitas, DateTime waktu) async {
    await _db.into(_db.syncState).insertOnConflictUpdate(
          SyncStateCompanion(
            entity: Value(entitas),
            lastPulledAt: Value(waktu),
          ),
        );
  }

  static DateTime? _waktu(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
