import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_database.dart';
import 'kemajuan_sync.dart';
import '../supabase/supabase_service.dart';

/// Hasil satu putaran sinkronisasi.
class HasilSync {
  /// Baris yang DITERIMA dari server.
  ///
  /// Sengaja dipisah dari [berubah]: server mengirim setiap baris yang lebih
  /// baru dari penanda kita, dan sebagian di antaranya ternyata sudah sama
  /// persis dengan yang ada di sini. Melaporkan angka ini ke pengguna sebagai
  /// "data diperbarui" adalah kebohongan kecil yang bikin bingung — mereka
  /// menekan segarkan pada daftar yang tidak berubah, lalu diberi tahu ada
  /// belasan data baru.
  final int diperiksa;

  /// Baris yang BENAR-BENAR mengubah isi database lokal: baris baru, atau
  /// baris yang versinya di server lebih baru. Ini yang layak ditampilkan.
  final int berubah;

  final int didorong;

  /// Berkas gambar yang berpindah. Dipisah dari [berubah] karena sinkron
  /// gambar berjalan sebagai tahap tersendiri dan boleh gagal sendirian.
  final int gambarNaik;
  final int gambarTurun;
  final int gambarDihapus;

  /// Kegagalan sinkron BARIS. Kegagalan gambar tidak ditaruh di sini supaya
  /// gambar yang gagal berpindah tidak membuat seluruh putaran dianggap gagal
  /// — transaksinya sendiri sudah aman terkirim.
  final String? error;

  /// Kegagalan sinkron GAMBAR, kalau ada.
  final String? errorGambar;

  const HasilSync({
    this.diperiksa = 0,
    this.berubah = 0,
    this.didorong = 0,
    this.gambarNaik = 0,
    this.gambarTurun = 0,
    this.gambarDihapus = 0,
    this.error,
    this.errorGambar,
  });

  bool get berhasil => error == null;

  /// Salin hasil ini sambil menambahkan hasil tahap gambar.
  HasilSync denganGambar({
    int naik = 0,
    int turun = 0,
    int hapus = 0,
    String? error,
  }) =>
      HasilSync(
        diperiksa: diperiksa,
        berubah: berubah,
        didorong: didorong,
        gambarNaik: naik,
        gambarTurun: turun,
        gambarDihapus: hapus,
        error: this.error,
        errorGambar: error,
      );

  @override
  String toString() {
    if (!berhasil) return 'GAGAL: $error';
    final g = errorGambar != null
        ? ', gambar GAGAL: $errorGambar'
        : (gambarNaik > 0 || gambarTurun > 0 || gambarDihapus > 0)
            ? ', gambar naik $gambarNaik turun $gambarTurun '
                'hapus $gambarDihapus'
            : '';
    return 'periksa $diperiksa, ubah $berubah, kirim $didorong$g';
  }
}

/// Satu tabel yang ikut disinkronkan.
///
/// Dibuat sebagai deskripsi, bukan kode terpisah per tabel, supaya menambah
/// tabel baru cukup menambah satu entri — bukan menyalin sepasang fungsi
/// dorong/tarik yang gampang beda halus satu sama lain.
class _Entitas {
  /// Nama tabel di PostgreSQL, sekaligus di SQLite.
  final String nama;

  /// Baris lokal yang belum terkirim, sudah diubah jadi bentuk JSON server.
  final Future<List<Map<String, dynamic>>> Function() ambilTertunda;

  /// Tulis satu baris dari server ke database lokal, TANPA pertimbangan
  /// apa pun.
  ///
  /// Keputusan boleh-tidaknya menulis sengaja TIDAK ditaruh di sini,
  /// melainkan terpusat di [SyncEngine._tarik]. Kalau setiap tabel memutuskan
  /// sendiri, tujuh salinan aturan yang sama akan berbeda halus satu sama
  /// lain — dan aturan inilah yang menentukan data pengguna hilang atau
  /// selamat.
  final Future<void> Function(Map<String, dynamic>) tulis;

  /// Tandai baris-baris ini sudah terkirim.
  final Future<void> Function(List<String>) tandaiTerkirim;

  const _Entitas({
    required this.nama,
    required this.ambilTertunda,
    required this.tulis,
    required this.tandaiTerkirim,
  });
}

/// Menyinkronkan database lokal dengan Supabase.
///
/// ── KENAPA TIDAK ADA TABEL OUTBOX TERPISAH ──
///
/// Kolom `sync_status` yang sudah ada DI SETIAP BARIS sudah berperan sebagai
/// antrean: baris bernilai 'pending' adalah baris yang belum terkirim.
///
/// Alternatifnya tabel antrean yang mencatat setiap operasi. Itu lebih setia
/// pada urutan kejadian, tapi tidak berguna di sini: penyelesaian konflik
/// memakai "yang terbaru menang". Kalau satu baris diubah tiga kali saat
/// offline, mengirim keadaan TERAKHIRNYA sekali menghasilkan yang sama
/// persis dengan memutar ulang tiga operasi — dengan sepertiga lalu lintas
/// dan tanpa tabel tambahan yang harus dijaga konsistensinya.
///
/// ── KENAPA PENGHAPUSAN TETAP TERKIRIM ──
///
/// Semua penghapusan bersifat lunak (`deleted_at` diisi, barisnya tetap
/// ada), jadi penghapusan terkirim sebagai perubahan biasa. Baris yang
/// benar-benar lenyap tidak bisa diberitahukan ke perangkat lain — server
/// hanya melihat ketiadaan, dan ketiadaan tidak bisa dikirim.
class SyncEngine {
  final AppDatabase _db;

  /// Dipanggil setiap kali ada kemajuan, supaya lapisan tampilan bisa
  /// menunjukkan apa yang sedang terjadi. Boleh null di test.
  final void Function(KemajuanSync)? onKemajuan;

  SyncEngine(this._db, {this.onKemajuan});

  SupabaseService get _supabase => SupabaseService.instance;

  /// URUTAN PENTING — induk sebelum anak.
  ///
  /// Server menegakkan foreign key. Mengirim transaksi sebelum shift-nya ada
  /// akan ditolak, dan mengirim item sebelum transaksinya ada juga. Urutan
  /// yang sama dipakai saat menarik, dengan alasan yang sama.
  late final List<_Entitas> _entitas = [
    _users(),
    _categories(),
    _products(),
    _shifts(),
    _transactions(),
    _transactionItems(),
    _expenses(),
  ];

  Future<HasilSync> jalankan() async {
    if (!_supabase.online) {
      return const HasilSync(error: 'offline atau perangkat belum didaftarkan');
    }
    try {
      var diperiksa = 0;
      var berubah = 0;
      // Tarik dulu semuanya, baru dorong. Mendorong lebih dulu bisa menimpa
      // perubahan server yang belum sempat dilihat perangkat ini.
      for (var i = 0; i < _entitas.length; i++) {
        final h = await _tarik(_entitas[i], i + 1);
        diperiksa += h.$1;
        berubah += h.$2;
      }
      var didorong = 0;
      for (var i = 0; i < _entitas.length; i++) {
        didorong += await _dorong(_entitas[i], i + 1);
      }
      return HasilSync(
        diperiksa: diperiksa,
        berubah: berubah,
        didorong: didorong,
      );
    } catch (e) {
      return HasilSync(error: e.toString());
    }
  }

  void _lapor(String tahap, String entitas, int urutan, int baris, int total,
      {int perubahan = 0}) {
    onKemajuan?.call(KemajuanSync(
      tahap: tahap,
      entitas: entitas,
      entitasKe: urutan,
      // Termasuk tahap gambar yang dikerjakan SyncGambar setelah ini. Kalau
      // dihitung 7 di sini lalu 8 di sana, bilah kemajuannya melompat mundur.
      totalEntitas: KemajuanSync.totalTahap,
      baris: baris,
      totalBaris: total,
      perubahan: perubahan,
    ));
  }

  // ------------------------------------------------------------------
  // TARIK / DORONG
  // ------------------------------------------------------------------

  /// Menarik satu tabel. Mengembalikan (baris diterima, baris benar-benar
  /// berubah).
  ///
  /// ── KENAPA VERSI SERVER TIDAK LANGSUNG DITIMPAKAN ──
  ///
  /// Sebelumnya baris server ditulis begitu saja lewat `insertOnConflictUpdate`
  /// tanpa membandingkan apa pun, sekaligus menyetel `sync_status = 'synced'`.
  /// Untuk baris yang punya perubahan lokal belum terkirim, akibatnya fatal
  /// dan senyap:
  ///
  /// ```
  /// 1. pengguna menambah gambar   -> lokal: image_path terisi, 'pending'
  /// 2. pengguna menyegarkan       -> TARIK dulu, baru DORONG
  /// 3. tarikan menimpa baris itu  -> image_path kembali NULL, jadi 'synced'
  /// 4. giliran dorong             -> tidak ada lagi yang 'pending'
  /// ```
  ///
  /// Gambarnya hilang dari layar DAN tidak pernah sampai ke server. Filenya
  /// tetap ada di disk tanpa ada yang menunjuknya.
  ///
  /// ── ATURANNYA MURNI PERBANDINGAN WAKTU ──
  ///
  /// | keadaan                        | tindakan                            |
  /// |--------------------------------|-------------------------------------|
  /// | belum ada barisnya di sini     | tulis — ini data baru               |
  /// | server lebih baru              | tulis — termasuk kalau isinya hapus |
  /// | waktunya sama persis           | lewati — versinya memang sama       |
  /// | lokal lebih baru               | lewati — jangan mundur              |
  ///
  /// Status `pending` sengaja TIDAK ikut jadi syarat, karena aturan waktu di
  /// atas sudah menanganinya sendiri: baris `pending` yang lebih baru akan
  /// dilewati sehingga statusnya tetap `pending` dan ikut terdorong di tahap
  /// berikutnya. Sebaliknya, penghapusan dari server yang lebih baru tetap
  /// menang — jadi produk yang dihapus pemilik tidak hidup lagi di HP kasir.
  ///
  /// Kasus seri (`waktunya sama persis`) memenangkan yang lokal. `updated_at`
  /// lokal beresolusi DETIK, jadi dua perubahan dalam detik yang sama tidak
  /// bisa dibedakan urutannya. Kalau ragu, yang belum terkirim lebih layak
  /// diselamatkan: ia hanya ada di perangkat ini, sedangkan versi server
  /// masih tersimpan di server dan bisa dikirim ulang.
  Future<(int, int)> _tarik(_Entitas e, int urutan) async {
    final sejak = await _kursorTarikTerakhir(e.nama);

    var query = _supabase.client!.from(e.nama).select();
    if (sejak != null) {
      query = query.gt('updated_at', sejak);
    }
    final baris = await query.order('updated_at');
    return _gabungkan(e, baris, urutan);
  }

  /// Menggabungkan baris dari server ke database lokal, tanpa menyentuh
  /// jaringan.
  ///
  /// Dipisah dari [_tarik] supaya aturan menang-kalah di bawah bisa diuji
  /// melawan database sungguhan tanpa perlu server — aturan inilah yang
  /// menentukan perubahan pengguna selamat atau hilang, jadi ia layak diuji
  /// langsung, bukan lewat tiruan.
  Future<(int, int)> _gabungkan(
    _Entitas e,
    List<Map<String, dynamic>> baris,
    int urutan,
  ) async {
    _lapor('menarik', e.nama, urutan, 0, baris.length);
    if (baris.isEmpty) return (0, 0);

    String? kursorTertinggi;
    var tertinggi = -1 << 62;
    var sudah = 0;
    var berubah = 0;

    for (final r in baris) {
      final waktuServer = r['updated_at'] as String;
      final mikroServer = _mikro(waktuServer);
      final lokal = await _keadaanLokal(e.nama, r['id'] as String);

      if (lokal == null || _serverMenang(lokal, mikroServer)) {
        await e.tulis(r);
        berubah++;
      }

      sudah++;
      // Dilaporkan berkala saja — memanggil setState seribu kali justru
      // membuat tampilan tersendat.
      if (sudah % 25 == 0 || sudah == baris.length) {
        _lapor('menarik', e.nama, urutan, sudah, baris.length,
            perubahan: berubah);
      }

      if (mikroServer > tertinggi) {
        tertinggi = mikroServer;
        kursorTertinggi = waktuServer;
      }
    }

    await _catatKursorTarik(e.nama, kursorTertinggi!);
    return (baris.length, berubah);
  }

  /// Pintu masuk untuk test: menggabungkan baris server ke tabel bernama
  /// [namaTabel]. Diperlukan karena `_Entitas` sengaja privat.
  @visibleForTesting
  Future<(int, int)> gabungkanTabel(
    String namaTabel,
    List<Map<String, dynamic>> baris,
  ) =>
      _gabungkan(_entitas.firstWhere((e) => e.nama == namaTabel), baris, 1);

  /// Keadaan baris lokal yang dipakai untuk memutuskan menang-kalah.
  ///
  /// Dibaca lewat SQL mentah karena berlaku untuk ketujuh tabel; menuliskan
  /// tujuh kueri drift yang identik hanya menambah tempat untuk salah ketik.
  /// Kolom `updated_at` berisi DETIK epoch (bawaan drift), dikalikan sejuta
  /// supaya sebanding dengan waktu server yang bermikrodetik.
  Future<({int mikro, bool pending})?> _keadaanLokal(
      String tabel, String id) async {
    final baris = await _db.customSelect(
      'SELECT updated_at, sync_status FROM $tabel WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (baris == null) return null;
    return (
      mikro: baris.read<int>('updated_at') * 1000000,
      pending: baris.read<String>('sync_status') == 'pending',
    );
  }

  /// Apakah versi server layak menimpa versi lokal.
  ///
  /// ── KENAPA BARIS `pending` DIBANDINGKAN PADA RESOLUSI DETIK ──
  ///
  /// Waktu lokal hanya beresolusi DETIK (bawaan drift), sedangkan server
  /// menyimpan MIKRODETIK. Begitu baris server disalin ke sini, pecahannya
  /// hilang — sehingga versi server selamanya terlihat "lebih baru" daripada
  /// salinan lokalnya sendiri:
  ///
  /// ```
  /// server : 10:04:11.430427
  /// lokal  : 10:04:11.000000   <- salinan baris yang SAMA, pecahan terbuang
  /// ```
  ///
  /// Untuk baris `synced` itu tidak berbahaya: tidak ada yang bisa hilang,
  /// paling-paling barisnya ditulis ulang dengan isi yang sama. Tapi untuk
  /// baris `pending` akibatnya fatal — pengguna yang mengedit pada detik yang
  /// sama dengan cap waktu server akan kehilangan editnya, padahal dalam
  /// kenyataan edit itu terjadi BELAKANGAN.
  ///
  /// Maka baris `pending` dibandingkan detik-lawan-detik: setara dengan
  /// presisi yang memang dimiliki sisi lokal. Seri berarti lokal bertahan —
  /// perubahan yang belum terkirim hanya ada di perangkat ini, sedangkan
  /// versi server masih aman tersimpan di server.
  static bool _serverMenang(
      ({int mikro, bool pending}) lokal, int mikroServer) {
    if (!lokal.pending) return mikroServer > lokal.mikro;
    const sejuta = 1000000;
    return (mikroServer ~/ sejuta) > (lokal.mikro ~/ sejuta);
  }

  /// Waktu ISO dari server jadi mikrodetik epoch, untuk dibandingkan.
  static int _mikro(String iso) =>
      DateTime.parse(iso).microsecondsSinceEpoch;

  Future<int> _dorong(_Entitas e, int urutan) async {
    final tertunda = await e.ambilTertunda();
    _lapor('mengirim', e.nama, urutan, 0, tertunda.length);
    if (tertunda.isEmpty) return 0;

    // Dikirim per potongan. Satu permintaan berisi ratusan baris gampang
    // melewati batas ukuran badan permintaan, dan kalau gagal seluruhnya
    // harus diulang dari nol.
    const ukuranPotongan = 100;
    for (var i = 0; i < tertunda.length; i += ukuranPotongan) {
      final potongan = tertunda.skip(i).take(ukuranPotongan).toList();
      await _supabase.client!.from(e.nama).upsert(potongan);
      await e.tandaiTerkirim(
          [for (final r in potongan) r['id'] as String]);
      _lapor('mengirim', e.nama, urutan,
          (i + potongan.length).clamp(0, tertunda.length), tertunda.length);
    }
    return tertunda.length;
  }

  /// Tandai baris sudah terkirim.
  ///
  /// `updated_at` SENGAJA tidak ikut diubah. Kolom itu menyatakan kapan
  /// datanya berubah menurut pengguna, bukan kapan ia terkirim — dan
  /// nilainya dipakai untuk memutuskan versi mana yang menang. Menyentuhnya
  /// di sini akan membuat baris ini selalu "menang" atas perubahan perangkat
  /// lain tanpa alasan.
  Future<void> _tandai(String tabel, List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.customUpdate(
      "UPDATE $tabel SET sync_status = 'synced' "
      "WHERE id IN (${List.filled(ids.length, '?').join(',')})",
      variables: [for (final id in ids) Variable.withString(id)],
    );
  }

  // ------------------------------------------------------------------
  // Deskripsi tiap tabel
  // ------------------------------------------------------------------

  _Entitas _users() => _Entitas(
        nama: 'users',
        ambilTertunda: () async {
          final r = await (_db.select(_db.users)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final u in r)
              {
                'id': u.id,
                'username': u.username,
                // Hash PIN ikut terkirim supaya kasir bisa login dari
                // perangkat lain. Aman: PBKDF2 120.000 iterasi, dan RLS
                // menutup tabel ini dari akses tanpa login.
                'pin_hash': u.pinHash,
                'salt': u.salt,
                'role': u.role,
                'is_active': u.isActive,
                'recovery_hash': u.recoveryHash,
                'recovery_salt': u.recoverySalt,
                'recovery_created_at': _iso(u.recoveryCreatedAt),
                'recovery_used_at': _iso(u.recoveryUsedAt),
                'recovery_attempts': u.recoveryAttempts,
                'recovery_locked_until': _iso(u.recoveryLockedUntil),
                'login_attempts': u.loginAttempts,
                'login_locked_until': _iso(u.loginLockedUntil),
                'created_at': _iso(u.createdAt),
                'updated_at': _iso(u.updatedAt),
                'deleted_at': _iso(u.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.users).insertOnConflictUpdate(UsersCompanion(
                id: Value(r['id'] as String),
                username: Value(r['username'] as String),
                pinHash: Value(r['pin_hash'] as String),
                salt: Value(r['salt'] as String),
                role: Value(r['role'] as String),
                isActive: Value(r['is_active'] as bool),
                recoveryHash: Value(r['recovery_hash'] as String?),
                recoverySalt: Value(r['recovery_salt'] as String?),
                recoveryCreatedAt: Value(_dt(r['recovery_created_at'])),
                recoveryUsedAt: Value(_dt(r['recovery_used_at'])),
                recoveryAttempts: Value((r['recovery_attempts'] as num).toInt()),
                recoveryLockedUntil: Value(_dt(r['recovery_locked_until'])),
                loginAttempts: Value((r['login_attempts'] as num).toInt()),
                loginLockedUntil: Value(_dt(r['login_locked_until'])),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('users', ids),
      );

  _Entitas _categories() => _Entitas(
        nama: 'categories',
        ambilTertunda: () async {
          final r = await (_db.select(_db.categories)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final c in r)
              {
                'id': c.id,
                'name': c.name,
                'icon_codepoint': c.iconCodepoint,
                'created_at': _iso(c.createdAt),
                'updated_at': _iso(c.updatedAt),
                'deleted_at': _iso(c.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.categories)
              .insertOnConflictUpdate(CategoriesCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                iconCodepoint: Value(r['icon_codepoint'] as int?),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('categories', ids),
      );

  _Entitas _products() => _Entitas(
        nama: 'products',
        ambilTertunda: () async {
          final r = await (_db.select(_db.products)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final p in r)
              {
                'id': p.id,
                'name': p.name,
                'price': p.price,
                'barcode': p.barcode,
                'category_id': p.categoryId,
                'has_spicy_option': p.hasSpicyOption,
                'image_path': p.imagePath,
                'created_at': _iso(p.createdAt),
                'updated_at': _iso(p.updatedAt),
                'deleted_at': _iso(p.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.products).insertOnConflictUpdate(ProductsCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                price: Value((r['price'] as num).toInt()),
                barcode: Value(r['barcode'] as String?),
                categoryId: Value(r['category_id'] as String?),
                hasSpicyOption: Value(r['has_spicy_option'] as bool),
                imagePath: Value(r['image_path'] as String?),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('products', ids),
      );

  _Entitas _shifts() => _Entitas(
        nama: 'shifts',
        ambilTertunda: () async {
          final r = await (_db.select(_db.shifts)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final s in r)
              {
                'id': s.id,
                'user_id': s.userId,
                'start_at': _iso(s.startAt),
                'end_at': _iso(s.endAt),
                'updated_at': _iso(s.updatedAt),
                'deleted_at': _iso(s.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.shifts).insertOnConflictUpdate(ShiftsCompanion(
                id: Value(r['id'] as String),
                userId: Value(r['user_id'] as String),
                startAt: Value(_dt(r['start_at'])!),
                endAt: Value(_dt(r['end_at'])),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('shifts', ids),
      );

  _Entitas _transactions() => _Entitas(
        nama: 'transactions',
        ambilTertunda: () async {
          final r = await (_db.select(_db.transactions)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final t in r)
              {
                'id': t.id,
                'invoice_no': t.invoiceNo,
                'total': t.total,
                'payment_method': t.paymentMethod,
                'cash_received': t.cashReceived,
                'change': t.change,
                'cashier_user_id': t.cashierUserId,
                'shift_id': t.shiftId,
                'order_type': t.orderType,
                'created_at': _iso(t.createdAt),
                'updated_at': _iso(t.updatedAt),
                'deleted_at': _iso(t.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.transactions)
              .insertOnConflictUpdate(TransactionsCompanion(
                id: Value(r['id'] as String),
                invoiceNo: Value(r['invoice_no'] as String),
                total: Value((r['total'] as num).toInt()),
                paymentMethod: Value(r['payment_method'] as String),
                cashReceived: Value((r['cash_received'] as num?)?.toInt()),
                change: Value((r['change'] as num?)?.toInt()),
                cashierUserId: Value(r['cashier_user_id'] as String?),
                shiftId: Value(r['shift_id'] as String?),
                orderType: Value(r['order_type'] as String),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('transactions', ids),
      );

  _Entitas _transactionItems() => _Entitas(
        nama: 'transaction_items',
        ambilTertunda: () async {
          final r = await (_db.select(_db.transactionItems)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final i in r)
              {
                'id': i.id,
                'transaction_id': i.transactionId,
                'product_id': i.productId,
                'product_name': i.productName,
                'qty': i.qty,
                'price_at_sale': i.priceAtSale,
                'subtotal': i.subtotal,
                'notes': i.notes,
                'created_at': _iso(i.createdAt),
                'updated_at': _iso(i.updatedAt),
                'deleted_at': _iso(i.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.transactionItems)
              .insertOnConflictUpdate(TransactionItemsCompanion(
                id: Value(r['id'] as String),
                transactionId: Value(r['transaction_id'] as String),
                productId: Value(r['product_id'] as String),
                productName: Value(r['product_name'] as String),
                qty: Value((r['qty'] as num).toInt()),
                priceAtSale: Value((r['price_at_sale'] as num).toInt()),
                subtotal: Value((r['subtotal'] as num).toInt()),
                notes: Value(r['notes'] as String?),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('transaction_items', ids),
      );

  _Entitas _expenses() => _Entitas(
        nama: 'expenses',
        ambilTertunda: () async {
          final r = await (_db.select(_db.expenses)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final e in r)
              {
                'id': e.id,
                'shift_id': e.shiftId,
                'user_id': e.userId,
                'updated_by_user_id': e.updatedByUserId,
                'description': e.description,
                'amount': e.amount,
                'created_at': _iso(e.createdAt),
                'updated_at': _iso(e.updatedAt),
                'deleted_at': _iso(e.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.expenses).insertOnConflictUpdate(ExpensesCompanion(
                id: Value(r['id'] as String),
                shiftId: Value(r['shift_id'] as String),
                userId: Value(r['user_id'] as String),
                updatedByUserId: Value(r['updated_by_user_id'] as String?),
                description: Value(r['description'] as String),
                amount: Value((r['amount'] as num).toInt()),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('expenses', ids),
      );

  // ------------------------------------------------------------------
  // Penanda waktu & konversi
  // ------------------------------------------------------------------

  /// Penanda posisi tarikan terakhir, berupa string ISO APA ADANYA dari
  /// server.
  ///
  /// Sengaja tidak pernah diubah jadi `DateTime`. Drift menyimpan `DateTime`
  /// dalam DETIK, sedangkan server memakai MIKRODETIK — sekali dikonversi,
  /// `2026-09-04T10:04:11.430427` menyusut jadi `...11.000000`. Penanda yang
  /// menyusut selalu lebih kecil dari nilai aslinya, sehingga baris terbaru
  /// ikut tertarik lagi di SETIAP sinkronisasi, selamanya.
  Future<String?> _kursorTarikTerakhir(String entitas) async {
    final baris = await (_db.select(_db.syncState)
          ..where((s) => s.entity.equals(entitas)))
        .getSingleOrNull();
    return baris?.lastPulledCursor;
  }

  Future<void> _catatKursorTarik(String entitas, String kursor) async {
    await _db.into(_db.syncState).insertOnConflictUpdate(SyncStateCompanion(
          entity: Value(entitas),
          lastPulledCursor: Value(kursor),
        ));
  }

  /// SQLite menyimpan waktu sebagai detik epoch tanpa zona; PostgreSQL pakai
  /// timestamptz. Konversi selalu lewat UTC supaya tidak bergeser saat
  /// perangkat berpindah zona waktu.
  static String? _iso(DateTime? v) => v?.toUtc().toIso8601String();

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
