import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/models/sale_line.dart';
import '../shared/auth/session_manager.dart';
import 'uuid_helper.dart';

part 'app_database.g.dart';
part 'models/report_models.dart';

/// =======================
/// TABLE: SYNC_STATE (v16)
/// =======================
///
/// Mengingat kapan terakhir setiap tabel ditarik dari server, supaya
/// penarikan berikutnya cukup meminta "baris yang berubah setelah waktu ini"
/// — bukan mengunduh ulang seluruh tabel tiap kali.
///
/// Tabel ini MURNI lokal: tidak ada padanannya di PostgreSQL dan tidak
/// pernah ikut disinkronkan.
class SyncState extends Table {
  /// Nama tabel yang dilacak, mis. 'products'.
  /// Dinamai `entity`, bukan `tableName`, karena drift sudah memakai nama itu.
  TextColumn get entity => text()();

  /// Nilai `updated_at` tertinggi yang sudah berhasil ditarik, DISIMPAN APA
  /// ADANYA sebagai string ISO dari server.
  ///
  /// SENGAJA `TextColumn`, bukan `DateTimeColumn`. Drift menyimpan `DateTime`
  /// sebagai DETIK epoch, sedangkan PostgreSQL menyimpan sampai MIKRODETIK:
  ///
  /// ```
  /// updated_at di server : 2026-09-04T10:04:11.430427+00:00
  /// kalau lewat DateTime : 2026-09-04T10:04:11.000000   <- .430427 hilang
  /// ```
  ///
  /// Watermark yang terpangkas selalu lebih kecil dari nilai aslinya, jadi
  /// kueri `updated_at > watermark` terus-menerus mengambil ulang baris yang
  /// sama di SETIAP sinkronisasi. Itu bukan cuma boros: digabung dengan
  /// penimpaan baris lokal, baris `pending` yang belum terkirim ikut hancur —
  /// persis penyebab gambar produk hilang setelah refresh.
  ///
  /// Nilai ini memang tidak pernah dipakai sebagai waktu, hanya dikirim balik
  /// ke server sebagai penanda posisi. Menyimpannya sebagai teks sekaligus
  /// menghilangkan konversi zona waktu yang tidak diperlukan.
  TextColumn get lastPulledCursor => text().nullable()();

  @override
  Set<Column> get primaryKey => {entity};
}

/// =======================
/// TABLE: CATEGORIES (modified in v10 — add business_id + sync fields)
/// =======================
class Categories extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get name => text()();
  IntColumn get iconCodepoint => integer().nullable()();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: PRODUCTS (modified in v10 — add business_id + sync fields)
/// =======================
class Products extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get name => text()();
  IntColumn get price => integer()();

  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();

  // Tiga kelompok pilihan yang ditanyakan di halaman Kasir. Lihat
  // `features/sales/models/pilihan_produk.dart` (v28 menambah Manis dan Es).
  BoolColumn get hasSpicyOption =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hasSweetOption =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hasIceOption =>
      boolean().withDefault(const Constant(false))();
  TextColumn get imagePath => text().nullable()();

  // Sync-friendly (NEW in v10 — note: existing createdAt renamed agar konsisten)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: TRANSACTIONS (modified in v10 — add business_id + sync fields)
/// =======================
class Transactions extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();

  /// Nomor nota yang TAMPIL di struk, mis. `TRX/18/07/26/081398`.
  ///
  /// Dipisah dari [id] (NEW in v11) karena keduanya punya kebutuhan yang
  /// bertabrakan: [id] harus unik lintas device untuk sync sehingga wajib
  /// UUID, sedangkan nomor nota harus mudah dibaca kasir dan pelanggan.
  TextColumn get invoiceNo => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  IntColumn get total => integer()();
  TextColumn get paymentMethod => text()();
  IntColumn get cashReceived => integer().nullable()();
  IntColumn get change => integer().nullable()();

  // FK ditambahkan di v14. Sebelumnya dua kolom ini TEXT polos, sehingga
  // transaksi bisa menunjuk shift atau kasir yang tidak ada tanpa ditolak
  // database. Tidak menghalangi soft delete — baris yang ditandai
  // `deleted_at` tetap ada, jadi acuannya tetap sah.
  TextColumn get cashierUserId =>
      text().nullable().references(Users, #id)();
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();

  /// SALINAN nama kasir saat transaksi dibuat (v35). Riwayat lama tidak ikut
  /// berubah saat akunnya diganti nama atau dihapus. Logika tetap memakai
  /// [cashierUserId]. Lihat `nama_tercatat.dart`.
  TextColumn get cashierName => text().nullable()();

  TextColumn get orderType =>
      text().withDefault(const Constant('dine_in'))();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Untuk transaksi artinya DIBATALKAN, bukan sampah. Transaksi tidak pernah
  /// dihapus — barisnya disimpan selamanya sebagai bukti, tampil di Riwayat
  /// dengan label DIBATALKAN, dan tidak dihitung di total mana pun (semua
  /// kueri laporan sudah menyaring `deletedAt`). Lihat [batalkanTransaksi].
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Siapa yang menekan "Batalkan" (v30). Kasir hanya bisa dengan PIN owner.
  TextColumn get cancelledByUserId =>
      text().nullable().references(Users, #id)();

  /// SALINAN nama yang membatalkan (v35).
  TextColumn get cancelledByName => text().nullable()();

  /// Alasan pembatalan (v30). Null untuk yang terhapus sebelum fitur ini.
  TextColumn get cancelReason => text().nullable()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  // NEW in v12. Kolom order_type pernah tercemar 163 baris bernilai
  // 'takeaway' (tanpa garis bawah) dari penyuntikan data langsung, dan
  // seluruhnya terhitung sebagai Dine In di laporan tanpa error apa pun.
  @override
  List<String> get customConstraints => [
        "CHECK (payment_method IN ('cash', 'qris'))",
        // 'take_away' tidak lagi dibuat aplikasi (digabung ke Dine In, v34),
        // tapi SENGAJA masih diterima: HP yang belum diperbarui masih bisa
        // membuatnya, dan baris yang ditolak akan macet saat sinkron.
        // Perketat setelah semua HP memakai APK v34.
        "CHECK (order_type IN ('dine_in', 'take_away', 'delivery'))",
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: TRANSACTION_ITEMS (modified in v10 — add business_id + sync fields)
/// =======================
class TransactionItems extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get transactionId => text()();
  // SENGAJA tanpa foreign key ke products (dilepas di v24).
  //
  // Di v14 sempat dipasang dengan alasan "membuang produk yang pernah laku
  // akan merusak riwayat penjualan". Alasan itu tidak berlaku: item struk
  // MENYALIN nama dan harganya sendiri (`productName`, `priceAtSale`), dan
  // tidak ada satu pun laporan yang mencari produk lewat kolom ini — "produk
  // terlaris" pun mengelompokkan berdasarkan nama salinan. Struk lama tetap
  // utuh walau produknya sudah tidak ada.
  //
  // Yang justru ditimbulkan rantai ini: produk tidak pernah bisa dibuang dari
  // server, dan kalau dibuang pun, HP yang baru dipasang akan MENOLAK item
  // struk lama yang menunjuknya — riwayatnya bolong tanpa pesan apa pun.
  //
  // Validitas id saat berjualan tetap dijaga aplikasi:
  // `_validasiProdukMasihAda` di dalam `createSale`.
  TextColumn get productId => text()();
  TextColumn get productName => text().withDefault(const Constant(''))();

  IntColumn get qty => integer()();
  IntColumn get priceAtSale => integer()();
  IntColumn get subtotal => integer()();

  TextColumn get notes => text().nullable()();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE',
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: USERS (modified in v10 — add sync fields. NO business_id karena global)
/// =======================
class Users extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get username => text().unique()();
  TextColumn get pinHash => text()();
  TextColumn get salt => text()();
  TextColumn get role => text()(); // 'owner' | 'cashier' — dijaga CHECK di v12
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  TextColumn get recoveryHash => text().nullable()();
  TextColumn get recoverySalt => text().nullable()();
  DateTimeColumn get recoveryCreatedAt => dateTime().nullable()();
  DateTimeColumn get recoveryUsedAt => dateTime().nullable()();
  IntColumn get recoveryAttempts =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get recoveryLockedUntil => dateTime().nullable()();

  IntColumn get loginAttempts =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get loginLockedUntil => dateTime().nullable()();

  /// Akun DIHAPUS (v35): disembunyikan permanen dari Kelola Kasir dan tidak
  /// bisa login lagi, tapi barisnya tetap ada karena riwayat menunjuknya
  /// lewat id. Beda dengan [isActive] = false (nonaktif, bisa diaktifkan
  /// lagi). Keputusan owner 2026-10-07.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  List<String> get customConstraints => [
        "CHECK (role IN ('owner', 'cashier'))",
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: SHIFTS (modified in v10 — add business_id + sync fields)
/// =======================
class Shifts extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get userId => text().references(Users, #id)();

  /// SALINAN nama kasir saat shift dibuka (v35) — untuk ditampilkan saja;
  /// logika tetap memakai [userId]. Lihat `nama_tercatat.dart`.
  TextColumn get userName => text().nullable()();
  DateTimeColumn get startAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endAt => dateTime().nullable()();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: PERMISSIONS
/// =======================
class Permissions extends Table {
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();

  @override
  Set<Column> get primaryKey => {code};
}

/// =======================
/// TABLE: USER_PERMISSIONS
/// =======================
/// Izin yang didapat kasir baru, dan yang diisi ulang untuk kasir yang
/// izinnya hilang.
///
/// Sengaja hanya dua. Melihat shift sendiri di Pantau Shift dan membuka menu
/// Riwayat adalah hak paten semua akun, bukan izin. `view_history` (melihat
/// catatan dari shift-shift yang sudah lewat) dan `view_all_shifts` (melihat
/// kasir lain) harus diberikan owner dengan sengaja.
///
/// Ditaruh di sini, bukan di repository, karena dipakai dua tempat: saat
/// membuat kasir baru dan saat migrasi mengisi ulang izin yang hilang. Dua
/// daftar terpisah pasti akan berbeda cepat atau lambat.
const _izinBawaanKasir = <String>[
  'open_close_shift',
  'create_transaction',
];

/// Dibaca repository supaya daftarnya hanya ada satu.
const izinBawaanKasir = _izinBawaanKasir;

class UserPermissions extends Table {
  /// Primary key TURUNAN dari (user_id, permission_code), bukan acak.
  ///
  /// Tabel ini lahir sebelum aturan "setiap tabel wajib UUID + updated_at +
  /// deleted_at + sync_status" ada, jadi ia memakai kunci gabungan dan tidak
  /// punya satu pun kolom sync. Akibatnya ia TIDAK PERNAH ikut disinkronkan —
  /// izin kasir hanya hidup di HP tempat owner mengaturnya, dan HP kasir yang
  /// dipasang ulang kehilangan seluruh izinnya. Kasirnya lumpuh: menu Kasir
  /// pun tidak muncul.
  ///
  /// Kenapa turunan, bukan acak: identitas baris ini ditentukan ISINYA — "izin
  /// X milik user Y" hanya boleh ada satu. Dengan UUID acak, dua perangkat
  /// yang membuat pasangan sama menghasilkan dua `id` berbeda, lalu batasan
  /// unik menolak yang kedua dan barisnya tertahan selamanya. Dengan UUID
  /// turunan, keduanya menghasilkan baris yang sama persis dan cukup saling
  /// menimpa.
  TextColumn get id => text()();

  TextColumn get userId => text()();
  TextColumn get permissionCode => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  List<String> get customConstraints => [
        'UNIQUE(user_id, permission_code)',
        'FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE',
        'FOREIGN KEY(permission_code) REFERENCES permissions(code) ON DELETE CASCADE',
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: EXPENSES
///
/// Pengeluaran tidak bisa DIEDIT dan tidak pernah DIHAPUS — yang salah
/// dibatalkan lalu dicatat ulang (v31). Sama seperti transaksi.
/// =======================
class Expenses extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  /// Null = pengeluaran OWNER (v33): owner tidak menjalankan shift, jadi
  /// pengeluarannya hanya dikelompokkan per tanggal. Pengeluaran kasir
  /// wajib punya shift — ditegakkan `ExpenseRepository.addExpense`.
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();
  @ReferenceName('createdExpensesRefs')
  TextColumn get userId => text().references(Users, #id)(); // creator

  /// SALINAN nama pencatat saat dicatat (v35). Lihat `nama_tercatat.dart`.
  TextColumn get userName => text().nullable()();
  TextColumn get description => text()();

  /// TOTAL (harga x [qty]) — semua laporan menjumlahkan kolom ini.
  IntColumn get amount => integer()();

  /// Kategori biaya (v32): 'asset' | 'bahan_baku' | 'operasional_kedai'.
  /// WAJIB — hanya tiga pilihan, tanpa "Lainnya" (keputusan owner
  /// 2026-10-04). Pengeluaran lama diisi Bahan Baku. Lihat `KategoriBiaya`.
  // Pola `.check()` drift memang merujuk kolomnya sendiri. CHECK level
  // kolom (bukan customConstraints tabel) supaya bisa ditambah lewat
  // ALTER TABLE ADD COLUMN saat migrasi.
  TextColumn get category => text()
      .withDefault(const Constant('bahan_baku'))
      // ignore: recursive_getters
      .check(category.isIn(const ['asset', 'bahan_baku', 'operasional_kedai']))();

  /// Jumlah barang (v32), minimal 1.
  IntColumn get qty => integer()
      .withDefault(const Constant(1))
      // ignore: recursive_getters
      .check(qty.isBiggerOrEqualValue(1))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Untuk pengeluaran artinya DIBATALKAN — disimpan selamanya, tampil
  /// berlabel, tidak dihitung di total. Lihat [batalkanPengeluaran].
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Siapa yang membatalkan (v31). Kasir hanya bisa dengan PIN owner.
  @ReferenceName('cancelledExpensesRefs')
  TextColumn get cancelledByUserId =>
      text().nullable().references(Users, #id)();

  /// SALINAN nama yang membatalkan (v35).
  TextColumn get cancelledByName => text().nullable()();

  /// Alasan pembatalan (v31). Null untuk yang terhapus sebelum fitur ini.
  TextColumn get cancelReason => text().nullable()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// DATABASE
/// =======================
@DriftDatabase(tables: [
  Products,
  Categories,
  Transactions,
  TransactionItems,
  Users,
  Shifts,
  Permissions,
  UserPermissions,
  Expenses,
  SyncState,          // v16 — penanda waktu sinkron, murni lokal
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 35;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedPermissions();
        },
        onUpgrade: (m, from, to) async {
          // C2: Setiap blok migrasi pakai lower bound `from < N && to >= N`
          // agar tidak double-addColumn ketika upgrade lompat banyak versi
          // (mis. v1 ke v9). `createTable` selalu pakai schema terkini, jadi
          // kolom yang ditambahkan di versi >N akan ikut terbuat — addColumn
          // berikutnya pada kolom yang sama akan throw "duplicate column".
          if (from < 2 && to >= 2) {
            await m.createTable(transactions);
            await m.createTable(transactionItems);
          }
          if (from < 3 && from >= 2 && to >= 3) {
            await m.addColumn(transactionItems, transactionItems.productName);
            await customStatement('''
              UPDATE transaction_items
              SET product_name = COALESCE(
                (SELECT name FROM products WHERE products.id = transaction_items.product_id),
                'Produk tidak diketahui'
              )
            ''');
          }
          if (from < 4 && to >= 4) {
            await m.createTable(categories);
            if (from >= 3) {
              await m.addColumn(products, products.categoryId);
            }
          }
          if (from < 5 && to >= 5) {
            await m.createTable(users);
            await m.createTable(shifts);
            await m.createTable(permissions);
            await m.createTable(userPermissions);
            if (from >= 2) {
              await m.addColumn(transactions, transactions.cashierUserId);
              await m.addColumn(transactions, transactions.shiftId);
            }
            await _seedPermissions();
          }
          if (from < 6 && from >= 5 && to >= 6) {
            await m.addColumn(users, users.recoveryHash);
            await m.addColumn(users, users.recoverySalt);
            await m.addColumn(users, users.recoveryCreatedAt);
            await m.addColumn(users, users.recoveryUsedAt);
            await m.addColumn(users, users.recoveryAttempts);
            await m.addColumn(users, users.recoveryLockedUntil);
          }
          if (from < 7 && to >= 7) {
            if (from >= 1) {
              await m.addColumn(products, products.hasSpicyOption);
              await m.addColumn(products, products.imagePath);
            }
            if (from >= 2) {
              await m.addColumn(transactionItems, transactionItems.notes);
              await m.addColumn(transactions, transactions.orderType);
            }
            await m.createTable(expenses);
          }
          if (from < 8 && from >= 4 && to >= 8) {
            await m.addColumn(categories, categories.iconCodepoint);
          }
          if (from < 9 && from >= 5 && to >= 9) {
            // S5: Login rate limiting
            await m.addColumn(users, users.loginAttempts);
            await m.addColumn(users, users.loginLockedUntil);
          }
          if (from < 10 && to >= 10) {
            // v10 — multi-business architecture migration (FRESH START per spec §5.4)
            // Karena data sekarang dummy (D13), drop semua tables lama + recreate
            // dengan schema multi-business.
            //
            // WARNING: ini DESTRUCTIVE. Setelah Phase 1 deploy ke client dengan data
            // real, pattern fresh-start TIDAK boleh dipakai lagi — Phase 2 wajib
            // preserve data.

            // Drop semua tables lama (urutan reverse FK)
            await m.deleteTable('expenses');
            await m.deleteTable('user_permissions');
            await m.deleteTable('permissions');
            await m.deleteTable('shifts');
            await m.deleteTable('users');
            await m.deleteTable('transaction_items');
            await m.deleteTable('transactions');
            await m.deleteTable('products');
            await m.deleteTable('categories');

            // Recreate semua tabel dengan skema saat itu
            await m.createAll();
            await _seedPermissions();
          }
          if (from < 11 && to >= 11) {
            // v11 — pisahkan nomor nota dari primary key.
            //
            // Sebelumnya `transactions.id` merangkap dua peran: primary key
            // sekaligus nomor nota yang tampil di struk. Formatnya berbasis
            // jam (TRX/dd/MM/yy/<mikrodetik>) sehingga rawan bentrok antar
            // device saat sync. Mulai v11 `id` murni UUID dan nomor notanya
            // pindah ke kolom sendiri.
            //
            // Non-destruktif: hanya ADD COLUMN + backfill.
            await m.addColumn(transactions, transactions.invoiceNo);
            // Baris lama memakai id sebagai nomor nota — salin apa adanya
            // supaya struk lama tetap menampilkan nomor yang sama.
            await customStatement(
              "UPDATE transactions SET invoice_no = id WHERE invoice_no = ''",
            );
          }
          if (from < 12 && to >= 12) {
            // v12 — pasang CHECK pada kolom yang berperan sebagai enum.
            //
            // SQLite tidak punya tipe ENUM, jadi kolom TEXT menerima salah
            // ketik apa pun tanpa protes. Ini sudah terbukti merugikan:
            // order_type sempat berisi 163 baris 'takeaway' (tanpa garis
            // bawah) sementara kode memakai 'take_away', dan semuanya
            // terhitung sebagai Dine In di laporan tanpa error apa pun.
            //
            // URUTAN PENTING: data dibersihkan DULU. Kalau tidak, pembangunan
            // ulang tabel akan gagal karena baris lama melanggar CHECK yang
            // baru dipasang.
            await customStatement(
              "UPDATE transactions SET order_type = 'take_away', "
              "updated_at = CAST(strftime('%s','now') AS INTEGER), "
              "sync_status = 'pending' WHERE order_type = 'takeaway'",
            );

            // alterTable membangun ulang tabel (SQLite tidak bisa
            // ALTER TABLE ADD CONSTRAINT) lalu menyalin seluruh datanya.
            //
            // TableMigration masih ditandai experimental oleh drift, tapi
            // dipakai karena bagian tersulitnya — menjaga acuan foreign key
            // dari tabel lain saat tabel dibangun ulang — sudah ditangani di
            // sana. Menulis prosedur 12 langkah SQLite sendiri justru lebih
            // rawan. Migrasi ini diuji pada database berisi 515 transaksi.
            // ignore_for_file: experimental_member_use
            await _bangunUlangTabel(m, transactions);
            await _bangunUlangTabel(m, users);
          }
          if (from < 13 && to >= 13) {
            // v13 — aplikasi difokuskan ke SATU bisnis.
            //
            // Kolom `business_id` dan tabel `businesses` /
            // `user_business_roles` dibuang seluruhnya. Peran user kini
            // dibaca dari `users.role` yang sudah ada — sebelumnya peran
            // punya dua sumber kebenaran, dan itu sudah pernah menimbulkan
            // bug (kasir dianggap owner).
            //
            // URUTAN PENTING: baris milik bisnis lain dihapus DULU. Kalau
            // kolomnya dibuang lebih dulu, data dua bisnis akan melebur jadi
            // satu dan laporan ikut salah.
            const bisnisDipertahankan = "SELECT id FROM businesses "
                "ORDER BY (name = 'Teras Inn') DESC, created_at ASC LIMIT 1";

            // Anak dulu, baru induk, supaya foreign key tidak terlanggar.
            for (final tabel in [
              'transaction_items',
              'transactions',
              'expenses',
              'shifts',
              'products',
              'categories',
            ]) {
              // Kalau tabel businesses kosong, subquery bernilai NULL dan
              // perbandingan `<>` ikut NULL — tidak ada baris yang terhapus.
              await customStatement(
                'DELETE FROM $tabel WHERE business_id <> ($bisnisDipertahankan)',
              );
            }

            // Bangun ulang tanpa kolom business_id. Induk dulu supaya acuan
            // foreign key dari tabel anak tetap sah saat disalin.
            await _bangunUlangTabel(m, categories);
            await _bangunUlangTabel(m, products);
            await _bangunUlangTabel(m, shifts);
            await _bangunUlangTabel(m, transactions);
            await _bangunUlangTabel(m, transactionItems);
            await _bangunUlangTabel(m, expenses);

            await m.deleteTable('user_business_roles');
            await m.deleteTable('businesses');
          }
          if (from < 14 && to >= 14) {
            // v14 — pasang foreign key yang selama ini hilang.
            //
            // `transactions.shift_id`, `transactions.cashier_user_id`, dan
            // `transaction_items.product_id` dulunya TEXT polos: database
            // menerima acuan ke baris yang tidak ada tanpa protes. Bandingkan
            // dengan `expenses` yang sejak awal punya FK.
            //
            // Ini penting menjelang sync. Selama data hanya lokal, baris
            // ngawur merusak satu perangkat. Setelah terpusat, ia menyebar ke
            // semua perangkat dan jauh lebih sulit dibereskan.
            //
            // Soft delete TIDAK terpengaruh: baris ber-`deleted_at` tetap ada
            // di tabel, jadi acuannya tetap sah.

            // URUTAN PENTING: bersihkan acuan yatim DULU. Membangun ulang
            // tabel dengan FK sementara masih ada baris yatim akan gagal di
            // tengah jalan. Emulator memang sudah bersih, tapi migrasi ini
            // harus aman juga di database yang tidak.
            await customStatement(
              'UPDATE transactions SET shift_id = NULL '
              'WHERE shift_id IS NOT NULL AND shift_id NOT IN '
              '(SELECT id FROM shifts)',
            );
            await customStatement(
              'UPDATE transactions SET cashier_user_id = NULL '
              'WHERE cashier_user_id IS NOT NULL AND cashier_user_id NOT IN '
              '(SELECT id FROM users)',
            );
            // product_id NOT NULL, jadi tidak bisa dikosongkan — item yang
            // menunjuk produk hantu memang tidak punya arti dan dibuang.
            await customStatement(
              'DELETE FROM transaction_items '
              'WHERE product_id NOT IN (SELECT id FROM products)',
            );

            // Induk dulu, baru anak.
            await _bangunUlangTabel(m, transactions);
            await _bangunUlangTabel(m, transactionItems);
          }
          if (from < 15 && to >= 15) {
            // v15 — `products.image_path` kini menyimpan path RELATIF
            // (products/<uuid>.webp), bukan path absolut.
            //
            // Baris lama menyimpan path apa adanya dari image_picker, yang
            // menunjuk folder CACHE aplikasi. Android boleh menghapus folder
            // itu kapan saja, jadi filenya cepat atau lambat lenyap sementara
            // path-nya tetap tersimpan — produk tampil dengan kotak kosong
            // dan tidak ada cara memulihkannya.
            //
            // Path absolut peninggalan versi lama dikosongkan: selain rawan
            // hilang, path absolut memuat lokasi instalasi yang di iOS
            // berubah setiap kali aplikasi di-update. Yang hilang hanya
            // gambarnya; produknya utuh dan owner tinggal mengunggah ulang.
            await customStatement(
              "UPDATE products SET image_path = NULL, "
              "updated_at = CAST(strftime('%s','now') AS INTEGER), "
              "sync_status = 'pending' "
              "WHERE image_path IS NOT NULL AND image_path LIKE '/%'",
            );
          }
          if (from < 16 && to >= 16) {
            // v16 — penanda waktu sinkron per tabel.
            await m.createTable(syncState);
          }
          if (from < 17 && to >= 17) {
            // v17 — buang dua kolom yang tidak lagi dipakai dari products.
            await _bangunUlangTabel(m, products);
          }
          if (from < 18 && to >= 18) {
            // v18 — watermark sinkron disimpan sebagai teks, bukan DateTime.
            //
            // Tabel ini murni cache posisi tarikan; tidak ada data pengguna di
            // dalamnya. Jadi dibuang dan dibuat ulang, bukan dikonversi —
            // konversi hanya akan memindahkan nilai yang SUDAH terpangkas,
            // yaitu nilai cacat yang justru mau dibuang.
            //
            // Akibatnya sinkronisasi berikutnya menarik satu kali penuh. Itu
            // aman HANYA karena penimpaan baris `pending` sudah diperbaiki di
            // rilis yang sama (lihat `SyncEngine.simpanDariServer`) — tanpa
            // itu, tarikan penuh justru akan menghapus perubahan lokal yang
            // belum terkirim di seluruh tabel.
            await m.deleteTable('sync_state');
            await m.createTable(syncState);
          }
          if (from < 19 && to >= 19) {
            // v19 — buang dua izin peninggalan arsitektur multi-bisnis.
            //
            // `manage_business` dan `switch_business` mengatur pemilihan usaha
            // aktif. Arsitektur itu sudah dihapus seluruhnya di v13, tapi baris
            // seed-nya tertinggal — jadi setiap pemasangan masih menyemai dua
            // izin yang tidak menjaga apa pun dan tidak bisa dipakai.
            //
            // Baris anaknya dibuang lebih dulu. ON DELETE CASCADE tidak
            // berlaku saat migrasi — SQLite mematikan penegakan foreign key
            // sepanjang proses, jadi menghapus induknya saja meninggalkan
            // baris yatim. Komentar lama di sini keliru; tidak ada akibat
            // nyata waktu itu hanya karena kebetulan tidak ada satu pun baris
            // yang menunjuk kedua izin tersebut.
            await customStatement(
              "DELETE FROM user_permissions "
              "WHERE permission_code IN ('manage_business','switch_business')",
            );
            await customStatement(
              "DELETE FROM permissions "
              "WHERE code IN ('manage_business','switch_business')",
            );
          }
          if (from < 20 && to >= 20) {
            // v20 — `user_permissions` akhirnya ikut disinkronkan.
            //
            // Tabel ini lahir sebelum aturan sync ada: kunci gabungan, tanpa
            // updated_at, tanpa sync_status. Jadi ia tidak pernah bisa ikut,
            // dan izin kasir hanya hidup di HP tempat owner mengaturnya. HP
            // kasir yang dipasang ulang kehilangan SELURUH izinnya — menu
            // Kasir pun tidak muncul dan kasirnya tidak bisa berjualan.
            // Terlihat langsung saat pengujian pemasangan baru.
            //
            // Dibuat ulang, bukan di-ALTER: kunci primernya berubah dari
            // gabungan menjadi `id`, dan SQLite tidak bisa mengubah kunci
            // primer di tempat.
            final lama = await customSelect(
              'SELECT user_id, permission_code, enabled FROM user_permissions',
            ).get();

            await customStatement('DROP TABLE user_permissions');
            await m.createTable(userPermissions);

            // `id` WAJIB turunan, bukan acak. Setiap HP menjalankan migrasi
            // ini sendiri-sendiri; kalau id-nya acak, HP owner dan HP kasir
            // menghasilkan dua id berbeda untuk pasangan yang SAMA. Keduanya
            // lalu didorong ke server dan yang kedua ditolak batasan unik —
            // barisnya tertahan selamanya tanpa sebab yang terlihat.
            for (final r in lama) {
              final uid = r.read<String>('user_id');
              final kode = r.read<String>('permission_code');
              await into(userPermissions).insert(
                UserPermissionsCompanion.insert(
                  id: uuidTurunan('$uid:$kode'),
                  userId: uid,
                  permissionCode: kode,
                  enabled: Value(r.read<bool>('enabled')),
                ),
                mode: InsertMode.insertOrIgnore,
              );
            }

            // Isi ulang izin bawaan untuk kasir yang TIDAK punya baris sama
            // sekali. Tanpa ini, memperbaiki sync saja tidak menolong: HP yang
            // terlanjur dipasang ulang datanya memang sudah lenyap, jadi
            // kasirnya tetap lumpuh.
            //
            // Daftar kasirnya diambil SEKALI di awal. Kalau diperiksa ulang di
            // tiap izin, penyisipan pertama membuat kasirnya "sudah punya
            // baris" dan tiga izin berikutnya ikut terlewat.
            final perluIsi = await customSelect(
              "SELECT id FROM users WHERE role = 'cashier' "
              "AND NOT EXISTS (SELECT 1 FROM user_permissions p "
              "                WHERE p.user_id = users.id)",
            ).get();

            for (final u in perluIsi) {
              final uid = u.read<String>('id');
              for (final kode in _izinBawaanKasir) {
                await into(userPermissions).insert(
                  UserPermissionsCompanion.insert(
                    id: uuidTurunan('$uid:$kode'),
                    userId: uid,
                    permissionCode: kode,
                    enabled: const Value(true),
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
              }
            }
          }
          if (from < 21 && to >= 21) {
            // v21 — empat izin diganti aturan paten, dan sisanya
            // diterjemahkan.
            //
            // `edit_own_expense`, `edit_any_expense`, `delete_own_transaction`,
            // dan `delete_any_transaction` bisa disetel ke kombinasi yang tidak
            // masuk akal: kasir yang diberi `delete_any_*` bisa menghapus
            // transaksi kasir LAIN, sedangkan pemilik yang lupa menyalakan
            // `edit_any_*` justru tidak bisa membetulkan pengeluaran anak
            // buahnya sendiri.
            //
            // Aturannya kini tetap: owner boleh mengubah catatan siapa pun,
            // selain owner hanya catatannya sendiri. Tidak ada lagi cara untuk
            // menyetelnya keliru. Sejak v30/v31 transaksi dan pengeluaran tidak lagi
            // dihapus/diedit, hanya dibatalkan — lihat `SalesRepository` dan
            // `ExpenseRepository` (`bolehDibatalkan`).
            //
            // Baris anaknya dibuang LEBIH DULU dan secara eksplisit.
            //
            // ON DELETE CASCADE TIDAK berlaku di sini: SQLite mematikan
            // penegakan foreign key selama migrasi, jadi menghapus induknya
            // saja meninggalkan baris `user_permissions` yatim yang menunjuk
            // kode yang sudah tidak ada. Terbukti saat menguji migrasi ini:
            // `PRAGMA foreign_key_check` melaporkan 2 pelanggaran dan izin
            // kasir tetap 3 baris padahal seharusnya tinggal 1.
            const dipatenkan = "('edit_own_expense','edit_any_expense',"
                "'delete_own_transaction','delete_any_transaction')";
            await customStatement(
              'DELETE FROM user_permissions WHERE permission_code IN '
              '$dipatenkan',
            );
            await customStatement(
              'DELETE FROM permissions WHERE code IN $dipatenkan',
            );

            // Nama dan keterangan yang tersisa ditulis ulang dalam bahasa
            // Indonesia. Disemai ulang, bukan sekadar untuk pemasangan baru:
            // pemasangan yang sudah ada masih menyimpan teks bahasa Inggris,
            // dan halaman Kelola Izin membacanya dari tabel ini.
            await _seedPermissions();
          }
          if (from < 22 && to >= 22) {
            // v22 — penanda tarik dikosongkan supaya tiap perangkat menarik
            // ulang sekali.
            //
            // Arti penandanya BERUBAH. Dulu berisi `updated_at` — jam perangkat
            // saat baris diubah. Sekarang berisi `server_urut` — jam server saat
            // baris tiba. Dua nilai itu tidak sebanding, dan membandingkannya
            // akan melewatkan baris diam-diam.
            //
            // Dikosongkan, bukan dikonversi: tidak ada rumus yang benar untuk
            // mengubah yang satu jadi yang lain. Menarik ulang aman karena
            // menggabungkan bersifat idempoten — baris yang isinya sama
            // dilewati, dan yang lokalnya lebih baru tetap menang.
            // Tabelnya belum tentu ada: migrasi bisa dijalankan dari versi
            // skema yang lebih tua daripada saat `sync_state` diperkenalkan,
            // dan SQLite menolak UPDATE ke tabel yang tidak ada saat kueri
            // disiapkan — sebelum WHERE mana pun sempat dievaluasi.
            final adaSyncState = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'sync_state'",
            ).get();
            if (adaSyncState.isNotEmpty) {
              await customStatement(
                  'UPDATE sync_state SET last_pulled_cursor = NULL');
            }
          }

          if (from < 23 && to >= 23) {
            // v23 — penanda dikosongkan sekali lagi.
            //
            // `supabase/sync_urutan.sql` versi pertama memberi cap "detik ini"
            // ke seluruh baris lama sekaligus, sehingga penanda tiap perangkat
            // mendarat di gumpalan itu dan setiap sinkron menarik ulang
            // seluruh tabel. `supabase/sync_urutan_perbaiki.sql` menyebar
            // capnya kembali mengikuti `updated_at`, dan nilai penanda yang
            // lama tidak lagi berarti apa-apa terhadap nilai yang baru.
            final adaSyncState = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'sync_state'",
            ).get();
            if (adaSyncState.isNotEmpty) {
              await customStatement(
                  'UPDATE sync_state SET last_pulled_cursor = NULL');
            }
          }

          if (from < 24 && to >= 24) {
            // v24 — rantai `transaction_items.product_id -> products` dilepas.
            //
            // SQLite tidak bisa mencopot foreign key dari tabel yang sudah
            // ada; satu-satunya jalan adalah membangun ulang tabelnya dengan
            // skema terbaru. Isinya disalin utuh — tidak ada baris yang
            // dibuang, karena justru item yang produknya sudah tiada kini SAH.
            //
            // Lihat catatan di kolom `TransactionItems.productId`.
            //
            // Dicek dulu tabelnya ada: migrasi bisa berangkat dari skema yang
            // lebih tua daripada saat tabel ini diperkenalkan, dan membangun
            // ulang tabel yang belum ada akan gagal.
            final adaItem = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'transaction_items'",
            ).get();
            if (adaItem.isNotEmpty) {
              await _bangunUlangTabel(m, transactionItems);
            }
          }

          if (from < 25 && to >= 25) {
            // v25 — penanda dikosongkan sekali lagi, karena tarikan lama
            // MELEWATKAN baris secara permanen.
            //
            // Dua kesalahan di penarikan bertahap (`SyncEngine._halaman`):
            // urutannya TURUN (bawaan `order()` di pustaka postgrest), dan
            // halaman berikutnya ditandai cap saja tanpa id. Tarikan yang
            // lebih dari satu halaman cuma mendapat baris terbaru, lalu
            // penandanya melompat melewati sisanya. Terbukti di HP yang
            // dipasang dari nol: 514 item struk dari 633.
            //
            // Menarik ulang dari nol mengisi yang bolong. Baris yang sudah
            // ada dan isinya sama dilewati, jadi aman.
            final adaSyncState = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'sync_state'",
            ).get();
            if (adaSyncState.isNotEmpty) {
              await customStatement(
                  'UPDATE sync_state SET last_pulled_cursor = NULL');
            }
          }

          if (from < 26 && to >= 26) {
            // v26 — kolom `users.deleted_at` dicopot. Akun tidak pernah
            // dihapus; karyawan yang keluar dinonaktifkan.
            //
            // DROP COLUMN, bukan membangun ulang tabel: `users` ditunjuk
            // banyak tabel lain, dan membangun ulang tabel induk berarti
            // membuang tabel lamanya dulu. Dicek dulu kolomnya ada, karena
            // pemasangan yang berangkat dari v10/v12 sudah membangun tabel
            // ini dari skema terbaru — tanpa kolom itu.
            final kolom = await customSelect(
              "SELECT 1 FROM pragma_table_info('users') "
              "WHERE name = 'deleted_at'",
            ).get();
            if (kolom.isNotEmpty) {
              await customStatement('ALTER TABLE users DROP COLUMN deleted_at');
            }
          }

          if (from < 27 && to >= 27) {
            // v27 — dua izin jadi hak PATEN, dan `view_history` berganti arti.
            //
            // - `manage_cashiers`: Kelola Kasir kini hanya untuk owner, tidak
            //   bisa diberikan — sama seperti Daftar Perangkat.
            // - `view_shift_reports`: melihat shift SENDIRI kini hak semua
            //   akun. Yang tetap izin hanya `view_all_shifts`.
            // - `view_history` kini berarti "boleh melihat shift-shift yang
            //   sudah lewat", bukan "boleh membuka menu Riwayat". Namanya
            //   disemai ulang; pencabutan dari kasir yang sudah memegangnya
            //   dilakukan di server supaya sampai ke semua HP.
            //
            // Anak dulu, baru induk — CASCADE tidak berlaku selama migrasi.
            // Lihat catatan v21.
            const dipatenkan = "('manage_cashiers','view_shift_reports')";
            await customStatement(
              'DELETE FROM user_permissions WHERE permission_code IN '
              '$dipatenkan',
            );
            await customStatement(
              'DELETE FROM permissions WHERE code IN $dipatenkan',
            );
            await _seedPermissions();
          }

          if (from < 28 && to >= 28) {
            // v28 — produk mendapat dua kelompok pilihan baru: Manis dan Es.
            //
            // Dicek dulu tabelnya ada (migrasi bisa berangkat dari skema yang
            // lebih tua — sama seperti v24), lalu per kolom: beberapa migrasi
            // lama membangun ulang tabel produk dari skema TERBARU, jadi
            // pemasangan yang berangkat dari sana sudah memiliki kolomnya.
            final adaProduk = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'products'",
            ).get();
            for (final kolom in [
              if (adaProduk.isNotEmpty) products.hasSweetOption,
              if (adaProduk.isNotEmpty) products.hasIceOption,
            ]) {
              final ada = await customSelect(
                "SELECT 1 FROM pragma_table_info('products') WHERE name = ?",
                variables: [Variable.withString(kolom.name)],
              ).get();
              if (ada.isEmpty) await m.addColumn(products, kolom);
            }
          }

          if (from < 29 && to >= 29) {
            // v29 — kolom `products.barcode` dicopot atas permintaan owner.
            // Barcode hanya diketik manual (tidak ada pemindai) dan tidak
            // dipakai pencarian; tidak ada produk yang mengisinya.
            //
            // DROP COLUMN, bukan membangun ulang tabel — `products` ditunjuk
            // tabel lain. Dicek dulu kolomnya ada (lihat v26).
            final kolom = await customSelect(
              "SELECT 1 FROM pragma_table_info('products') "
              "WHERE name = 'barcode'",
            ).get();
            if (kolom.isNotEmpty) {
              await customStatement('ALTER TABLE products DROP COLUMN barcode');
            }
          }

          if (from < 30 && to >= 30) {
            // v30 — transaksi tidak lagi dihapus, hanya DIBATALKAN dengan
            // siapa dan alasannya. Lihat [batalkanTransaksi].
            final adaTrx = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'transactions'",
            ).get();
            for (final kolom in [
              if (adaTrx.isNotEmpty) transactions.cancelledByUserId,
              if (adaTrx.isNotEmpty) transactions.cancelReason,
            ]) {
              final ada = await customSelect(
                "SELECT 1 FROM pragma_table_info('transactions') WHERE name = ?",
                variables: [Variable.withString(kolom.name)],
              ).get();
              if (ada.isEmpty) await m.addColumn(transactions, kolom);
            }
          }

          if (from < 31 && to >= 31) {
            // v31 — pengeluaran tidak lagi dihapus atau diedit, hanya
            // DIBATALKAN dengan siapa dan alasannya. Kolom
            // `updated_by_user_id` (siapa yang terakhir mengedit/menghapus)
            // dicopot: fiturnya sudah tidak ada.
            final adaPengeluaran = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'expenses'",
            ).get();
            if (adaPengeluaran.isNotEmpty) {
              Future<bool> ada(String nama) async => (await customSelect(
                    "SELECT 1 FROM pragma_table_info('expenses') WHERE name = ?",
                    variables: [Variable.withString(nama)],
                  ).get())
                      .isNotEmpty;
              for (final kolom in [
                expenses.cancelledByUserId,
                expenses.cancelReason,
              ]) {
                if (!await ada(kolom.name)) await m.addColumn(expenses, kolom);
              }
              if (await ada('updated_by_user_id')) {
                await customStatement(
                    'ALTER TABLE expenses DROP COLUMN updated_by_user_id');
              }
            }
          }

          if (from < 32 && to >= 32) {
            // v32 — kategori biaya dan jumlah pengeluaran (desain baru).
            // Kolom kategori wajib dengan bawaan 'bahan_baku', jadi
            // pengeluaran lama otomatis masuk Bahan Baku.
            final adaPengeluaran = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'expenses'",
            ).get();
            if (adaPengeluaran.isNotEmpty) {
              for (final kolom in [expenses.category, expenses.qty]) {
                final ada = await customSelect(
                  "SELECT 1 FROM pragma_table_info('expenses') WHERE name = ?",
                  variables: [Variable.withString(kolom.name)],
                ).get();
                if (ada.isEmpty) await m.addColumn(expenses, kolom);
              }
            }
          }

          if (from < 33 && to >= 33) {
            // v33 — `expenses.shift_id` boleh kosong untuk pengeluaran owner.
            // SQLite tidak bisa melepas NOT NULL dari kolom yang sudah ada;
            // tabelnya dibangun ulang dengan skema terbaru, isinya disalin
            // utuh (pola yang sama dengan v24).
            final adaPengeluaran = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'expenses'",
            ).get();
            if (adaPengeluaran.isNotEmpty) {
              await _bangunUlangTabel(m, expenses);
            }
          }

          if (from < 34 && to >= 34) {
            // v34 — Take Away digabung ke Dine In (permintaan owner
            // 2026-10-05). Barisnya ditandai pending dengan updated_at baru,
            // jadi sinkron ikut mengubahnya di server — tanpa berkas SQL.
            final adaTransaksi = await customSelect(
              "SELECT 1 FROM sqlite_master "
              "WHERE type = 'table' AND name = 'transactions'",
            ).get();
            if (adaTransaksi.isNotEmpty) {
              await customStatement(
                "UPDATE transactions SET order_type = 'dine_in', "
                "updated_at = CAST(strftime('%s','now') AS INTEGER), "
                "sync_status = 'pending' WHERE order_type = 'take_away'",
              );
            }
          }

          if (from < 35 && to >= 35) {
            // v35 — salinan nama akun di shift, transaksi, pengeluaran (dan
            // nama pembatal), plus users.deleted_at untuk Hapus Akun.
            // Pasangannya di server: supabase/salinan_nama_akun.sql.
            Future<bool> adaTabel(String t) async => (await customSelect(
                  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
                  variables: [Variable.withString(t)],
                ).get())
                .isNotEmpty;
            Future<void> tambah(TableInfo tabel, GeneratedColumn kolom) async {
              if (!await adaTabel(tabel.actualTableName)) return;
              final ada = await customSelect(
                "SELECT 1 FROM pragma_table_info(?) WHERE name = ?",
                variables: [
                  Variable.withString(tabel.actualTableName),
                  Variable.withString(kolom.name),
                ],
              ).get();
              if (ada.isEmpty) await m.addColumn(tabel, kolom);
            }

            await tambah(users, users.deletedAt);
            await tambah(shifts, shifts.userName);
            await tambah(transactions, transactions.cashierName);
            await tambah(transactions, transactions.cancelledByName);
            await tambah(expenses, expenses.userName);
            await tambah(expenses, expenses.cancelledByName);

            // Data lama diisi nama akun saat ini — hasilnya sama dengan isian
            // SQL server, jadi barisnya SENGAJA tidak ditandai pending.
            for (final (tabel, kolom, acuan) in const [
              ('shifts', 'user_name', 'user_id'),
              ('transactions', 'cashier_name', 'cashier_user_id'),
              ('transactions', 'cancelled_by_name', 'cancelled_by_user_id'),
              ('expenses', 'user_name', 'user_id'),
              ('expenses', 'cancelled_by_name', 'cancelled_by_user_id'),
            ]) {
              if (!await adaTabel(tabel)) continue;
              await customStatement(
                'UPDATE $tabel SET $kolom = '
                '(SELECT username FROM users WHERE users.id = $tabel.$acuan) '
                'WHERE $kolom IS NULL AND $acuan IS NOT NULL',
              );
            }
          }

        },
        beforeOpen: (details) async {
          if (details.wasCreated || (details.hadUpgrade && details.versionBefore! < 5)) {
            await _seedPermissions();
          }
          // SQLite mematikan penegakan foreign key secara default (alasan
          // kompatibilitas versi lama). Tanpa baris ini, semua `REFERENCES`
          // di skema hanya jadi dokumentasi: baris yatim tetap bisa masuk dan
          // ON DELETE CASCADE tidak jalan.
          //
          // Ditaruh di beforeOpen (bukan di dalam transaction) karena pragma
          // ini tidak bisa diubah di dalam transaksi — sesuai anjuran docs drift.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Bangun ulang [tabel] dengan skema TERBARU, menyalin seluruh isinya.
  ///
  /// `TableMigration` menyalin semua kolom skema terbaru dari tabel lama.
  /// Kolom yang belum ada di tabel lama WAJIB disebut sebagai `newColumns`,
  /// kalau tidak salinannya gagal ("N columns but M values"). Selama setiap
  /// kolom baru kebetulan sudah ada saat migrasi lama berjalan, ini tidak
  /// terasa — sampai v35 menambah kolom dan HP yang melompat dari v32 gagal
  /// di migrasi v33. Maka kolom yang belum ada dihitung dari tabelnya
  /// sendiri, untuk lompatan versi berapa pun.
  Future<void> _bangunUlangTabel(Migrator m, TableInfo tabel) async {
    final ada = {
      for (final r in await customSelect(
        'SELECT name FROM pragma_table_info(?)',
        variables: [Variable.withString(tabel.actualTableName)],
      ).get())
        r.read<String>('name'),
    };
    await m.alterTable(
      TableMigration(
        tabel,
        newColumns: [
          for (final c in tabel.$columns)
            if (!ada.contains(c.name)) c,
        ],
      ),
    );
  }

  Future<void> _seedPermissions() async {
    // Bahasa Indonesia, karena yang membacanya pemilik warung — bukan
    // pengembang. "Edit Any Expense (owner override)" tidak berarti apa-apa
    // bagi orang yang sedang mengatur akses kasirnya.
    //
    // Empat kode dibuang di v21 dan diganti aturan paten: `edit_own_expense`,
    // `edit_any_expense`, `delete_own_transaction`, `delete_any_transaction`.
    // Sekarang owner selalu boleh mengubah catatan siapa pun, dan selain owner
    // hanya catatannya sendiri — sejak v30/v31 lewat `bolehDibatalkan` di
    // `SalesRepository` dan `ExpenseRepository`.
    const permissionsData = [
      {
        'code': 'open_close_shift',
        'name': 'Buka & Tutup Shift',
        'description': 'Memulai dan mengakhiri jam kerja'
      },
      {
        'code': 'create_transaction',
        'name': 'Buat Transaksi',
        'description': 'Melayani penjualan di halaman Kasir'
      },
      {
        'code': 'view_history',
        'name': 'Lihat Riwayat Lengkap',
        'description': 'Melihat transaksi dan pengeluaran sendiri dari '
            'shift-shift sebelumnya. Tanpa izin ini hanya shift yang sedang '
            'berjalan'
      },
      {
        'code': 'view_report',
        'name': 'Lihat Laporan',
        'description': 'Membuka analisis penjualan'
      },
      {
        'code': 'manage_products',
        'name': 'Kelola Produk',
        'description': 'Menambah, mengubah, dan menghapus produk'
      },
      {
        'code': 'view_all_shifts',
        'name': 'Lihat Shift Semua Kasir',
        'description': 'Melihat shift kasir lain, bukan hanya miliknya sendiri'
      },
    ];

    for (final perm in permissionsData) {
      await into(permissions).insertOnConflictUpdate(
        PermissionsCompanion.insert(
          code: perm['code']!,
          name: perm['name']!,
          description: perm['description']!,
        ),
      );
    }
  }

  // ---- CATEGORIES ----

  Stream<List<Category>> watchCategories() {
    return (select(categories)
          ..where((t) =>
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<void> upsertCategory({
    required String id,
    required String name,
    int? iconCodepoint,
  }) async {
    SessionManager.instance.requirePermission('manage_products');
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion(
        id: Value(id),
        name: Value(name),
        iconCodepoint: Value(iconCodepoint),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Soft delete kategori: produk dilepas jadi tanpa kategori, lalu kategori
  /// ditandai terhapus.
  ///
  /// Sengaja TIDAK menghapus baris secara fisik. Baris yang lenyap tidak bisa
  /// diberitahukan ke device lain saat sync — server hanya melihat ketiadaan,
  /// dan ketiadaan tidak bisa dikirim. Akibatnya baris yang sudah dihapus akan
  /// dikirim balik oleh server dan "hidup lagi" (zombie record). Dengan
  /// menandai `deleted_at`, penghapusannya ikut tersinkron.
  Future<void> deleteCategory(String id) async {
    SessionManager.instance.requirePermission('manage_products');
    final now = DateTime.now();
    await transaction(() async {
      await (update(products)..where((p) => p.categoryId.equals(id)))
          .write(ProductsCompanion(
        categoryId: const Value(null),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ));
      await (update(categories)..where((t) => t.id.equals(id)))
          .write(CategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ));
    });
  }

  // ---- PRODUCTS ----

  Stream<List<Product>> watchProducts() {
    return (select(products)
          ..where((p) =>
              p.deletedAt.isNull()))
        .watch();
  }

  Future<void> upsertProduct({
    required String id,
    required String name,
    required int price,
    String? categoryId,
    required bool hasSpicyOption,
    required bool hasSweetOption,
    required bool hasIceOption,
    String? imagePath,
  }) async {
    SessionManager.instance.requirePermission('manage_products');
    final data = ProductsCompanion(
      id: Value(id),
      name: Value(name),
      price: Value(price),
      categoryId: Value(categoryId),
      hasSpicyOption: Value(hasSpicyOption),
      hasSweetOption: Value(hasSweetOption),
      hasIceOption: Value(hasIceOption),
      imagePath: Value(imagePath),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    );
    await into(products).insertOnConflictUpdate(data);
  }

  /// Soft delete produk — lihat catatan di [deleteCategory] soal zombie record.
  Future<void> deleteProduct(String id) async {
    SessionManager.instance.requirePermission('manage_products');
    final now = DateTime.now();
    await (update(products)..where((t) => t.id.equals(id)))
        .write(ProductsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value('pending'),
    ));
  }

  // ---- SAMPAH LOKAL ----

  /// Berapa lama baris yang sudah dihapus tetap disimpan di HP ini.
  static const umurSampahLokal = Duration(days: 30);

  /// Buang permanen dari HP ini produk dan kategori yang sudah dihapus DAN
  /// sudah sampai di server, setelah lewat [umurSampahLokal]. Transaksi dan
  /// pengeluaran tidak pernah — yang terhapus adalah yang dibatalkan, dan itu
  /// disimpan selamanya. Pasangan `buang_sampah` di server.
  ///
  /// Aman karena `synced` berarti server sudah tahu barisnya terhapus, jadi
  /// salinan di sini tidak dibutuhkan siapa pun. Baris yang masih `pending`
  /// TIDAK disentuh: kabar hapusnya belum terkirim, dan kalau dibuang di sini
  /// kabar itu hilang selamanya — barisnya tetap hidup di HP lain.
  ///
  /// Kalau server suatu saat mengirim baris itu lagi (misalnya saat penanda
  /// tarikan dikosongkan), ia masuk lagi sebagai "terhapus" dan dibuang lagi
  /// nanti. Tidak ada data aktif yang bisa hilang.
  Future<Map<String, int>> buangSampahLokal({DateTime? sekarang}) async {
    final batas = (sekarang ?? DateTime.now()).subtract(umurSampahLokal);
    final hasil = <String, int>{};

    await transaction(() async {
      // Transaksi dan pengeluaran SENGAJA tidak dibuang: yang `deletedAt`-nya
      // terisi adalah yang DIBATALKAN — bukti untuk owner, disimpan selamanya.
      // Lihat [batalkanTransaksi] dan [batalkanPengeluaran].

      hasil['produk'] = await (delete(products)
            ..where((p) =>
                p.deletedAt.isSmallerThanValue(batas) &
                p.syncStatus.equals('synced')))
          .go();

      // Sesudah produk. Kategori yang masih ditunjuk produk dilewati — itu
      // bisa terjadi kalau HP lain yang offline memasukkan produk ke kategori
      // yang sudah dihapus. Penjaga yang sama ada di `buang_sampah` server.
      hasil['kategori'] = await (delete(categories)
            ..where((c) =>
                c.deletedAt.isSmallerThanValue(batas) &
                c.syncStatus.equals('synced') &
                notExistsQuery(select(products)
                  ..where((p) => p.categoryId.equalsExp(c.id)))))
          .go();
    });

    return hasil;
  }

  // ---- SALES ----

  /// Catat penjualan. Mengembalikan nomor nota yang tercetak di struk.
  ///
  /// Nomor nota dibuat DI SINI, bukan di UI, supaya menghitung nomor dan
  /// menyimpan transaksi terjadi dalam satu transaction database. Kalau
  /// dipisah, ada celah di mana dua checkout bisa membaca hitungan yang sama.
  Future<String> createSale({
    required String transactionId,
    required List<SaleLine> lines,
    required String paymentMethod,
    required String orderType,
    int? cashReceived,
    String? cashierUserId,
    String? shiftId,
    required String kodePerangkat,
  }) async {
    // M-A: Defense-in-depth — selain UI yang sudah hide tombol "Kasir",
    // DB layer juga reject jika permission tidak ada.
    SessionManager.instance.requirePermission('create_transaction');

    if (lines.isEmpty) throw ArgumentError('Keranjang masih kosong');

    final total = lines.fold<int>(0, (s, l) => s + l.subtotal);

    if (paymentMethod == 'cash') {
      if (cashReceived == null) {
        throw ArgumentError('Uang diterima wajib diisi untuk pembayaran tunai');
      }
      if (cashReceived < total) {
        throw ArgumentError('Uang diterima kurang');
      }
    }

    final changeAmount =
        paymentMethod == 'cash' ? (cashReceived! - total) : null;

    late String invoiceNo;
    await transaction(() async {
      await _validasiProdukMasihAda(lines);
      invoiceNo = await _nextInvoiceNo(DateTime.now(), kodePerangkat);

      await into(transactions).insert(
        TransactionsCompanion(
          id: Value(transactionId),
          invoiceNo: Value(invoiceNo),
          total: Value(total),
          paymentMethod: Value(paymentMethod),
          cashReceived: Value(cashReceived),
          change: Value(changeAmount),
          cashierUserId: Value(cashierUserId),
          cashierName: Value(await usernameAkun(cashierUserId)),
          shiftId: Value(shiftId),
          orderType: Value(orderType),
          syncStatus: const Value('pending'),
        ),
      );

      await _insertTransactionItems(transactionId, lines);
    });
    return invoiceNo;
  }

  /// Nomor nota berikutnya untuk hari ini: `TRX/dd/MM/yy/KODE-NNNN`.
  ///
  /// Menghitung SELURUH transaksi hari ini termasuk yang sudah ditandai
  /// terhapus. Itu disengaja: kalau yang terhapus tidak ikut dihitung, nomor
  /// bekasnya akan dipakai ulang dan dua struk berbeda punya nomor yang sama —
  /// persis masalah yang mau dihilangkan. Ini bisa dilakukan karena penghapusan
  /// transaksi memakai soft delete, jadi barisnya tetap ada.
  ///
  /// Dipanggil dari DALAM transaction milik [createSale] supaya menghitung dan
  /// menyimpan tidak bisa disela.
  /// [kodePerangkat] adalah penanda pendek milik HP ini. Tanpa itu, dua HP
  /// yang sama-sama sudah mencatat 10 transaksi hari ini akan sama-sama
  /// menerbitkan nomor ke-11 — dua struk berbeda dengan nomor sama, dan
  /// server tidak menolaknya karena `invoice_no` tidak unik. Urutannya tetap
  /// dihitung lokal supaya nomor nota tidak butuh internet.
  Future<String> _nextInvoiceNo(DateTime now, String kodePerangkat) async {
    final awalHari = DateTime(now.year, now.month, now.day);
    final akhirHari = awalHari.add(const Duration(days: 1));

    final hitung = transactions.id.count();
    final baris = await (selectOnly(transactions)
          ..addColumns([hitung])
          ..where(transactions.createdAt.isBiggerOrEqualValue(awalHari) &
              transactions.createdAt.isSmallerThanValue(akhirHari)))
        .getSingle();
    final urut = (baris.read(hitung)! + 1).toString().padLeft(4, '0');

    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yy = (now.year % 100).toString().padLeft(2, '0');
    return 'TRX/$dd/$mm/$yy/$kodePerangkat-$urut';
  }

  /// Pastikan setiap produk di keranjang masih ada.
  ///
  /// Kasusnya nyata: kasir membuka halaman Kasir, pemilik menghapus sebuah
  /// produk dari HP-nya, lalu kasir menekan produk yang sudah tidak ada itu.
  /// Tanpa pemeriksaan ini, item transaksi akan menunjuk produk yang tidak
  /// ada dan ditolak foreign key dengan pesan yang tidak bisa dipahami kasir.
  Future<void> _validasiProdukMasihAda(List<SaleLine> lines) async {
    for (final line in lines) {
      final ada = await (select(products)
            ..where((t) => t.id.equals(line.productId) & t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

      if (ada == null) {
        throw StateError(
          '"${line.productName}" sudah tidak tersedia. '
          'Hapus produk ini dari keranjang sebelum melanjutkan.',
        );
      }
    }
  }

  Future<void> _insertTransactionItems(
    String transactionId,
    List<SaleLine> lines,
  ) async {
    for (final line in lines) {
      final itemId = newUuid();

      await into(transactionItems).insert(
        TransactionItemsCompanion(
          id: Value(itemId),
          transactionId: Value(transactionId),
          productId: Value(line.productId),
          productName: Value(line.productName),
          qty: Value(line.qty),
          priceAtSale: Value(line.priceAtSale),
          subtotal: Value(line.subtotal),
          notes: Value(line.notes),
          syncStatus: const Value('pending'),
        ),
      );
    }
  }

  // ---- TRANSACTIONS / HISTORY ----

  /// Transaksi yang belum dihapus, terbaru dulu.
  ///
  /// [kasirId] membatasi ke transaksi satu kasir; [shiftId] ke satu shift.
  /// Keduanya null berarti semua — hanya untuk owner. Siapa melihat apa
  /// diputuskan `CakupanRiwayat`, bukan di sini.
  ///
  /// [termasukBatal] ikut menampilkan transaksi yang dibatalkan — hanya untuk
  /// halaman Riwayat, yang memberinya label dan tidak menghitungnya.
  Stream<List<Transaction>> watchTransactions({
    String? kasirId,
    String? shiftId,
    bool termasukBatal = false,
  }) {
    return (select(transactions)
          ..where((t) =>
              termasukBatal ? const Constant(true) : t.deletedAt.isNull())
          ..where((t) =>
              kasirId == null ? const Constant(true) : t.cashierUserId.equals(kasirId))
          ..where((t) =>
              shiftId == null ? const Constant(true) : t.shiftId.equals(shiftId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Item satu transaksi. [termasukBatal] untuk struk transaksi yang
  /// dibatalkan — itemnya ikut bertanda terhapus, tapi isinya tetap perlu
  /// terlihat sebagai bukti.
  Future<List<TransactionItem>> getTransactionItems(
    String transactionId, {
    bool termasukBatal = false,
  }) async {
    return (select(transactionItems)
          ..where((t) =>
              t.transactionId.equals(transactionId) &
              (termasukBatal ? const Constant(true) : t.deletedAt.isNull())))
        .get();
  }

  /// Id transaksi yang punya item bernama mengandung [kata] (tanpa beda
  /// huruf besar/kecil) — untuk "Cari riwayat" berdasarkan nama menu. Item
  /// transaksi yang dibatalkan ikut, karena transaksinya tetap tampil.
  Future<Set<String>> idTransaksiBerisiMenu(String kata) async {
    // `%` dan `_` adalah wildcard LIKE — diloloskan supaya dicari apa adanya.
    final aman = kata
        .trim()
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    if (aman.isEmpty) return {};
    final baris = await customSelect(
      r"SELECT DISTINCT transaction_id FROM transaction_items "
      r"WHERE product_name LIKE ? ESCAPE '\'",
      variables: [Variable.withString('%$aman%')],
      readsFrom: {transactionItems},
    ).get();
    return {for (final b in baris) b.read<String>('transaction_id')};
  }

  /// Username akun [id] SAAT INI — untuk salinan nama di catatan baru
  /// (v35, lihat `nama_tercatat.dart`). Null kalau id kosong/tidak dikenal.
  Future<String?> usernameAkun(String? id) async {
    if (id == null) return null;
    final u = await (select(users)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    return u?.username;
  }

  /// Nama akun per id — untuk menampilkan siapa yang membatalkan.
  Future<Map<String, String>> namaAkun() async => {
        for (final u in await select(users).get()) u.id: u.username,
      };

  // ---- EXPENSES ----

  /// [termasukBatal] ikut menampilkan pengeluaran yang dibatalkan — hanya
  /// untuk halaman Pengeluaran, yang memberinya label dan tidak menghitungnya.
  Stream<List<Expense>> watchExpensesByShift(
    String shiftId, {
    bool termasukBatal = false,
  }) {
    return (select(expenses)
          ..where((e) =>
              e.shiftId.equals(shiftId) &
              (termasukBatal ? const Constant(true) : e.deletedAt.isNull()))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  /// Pengeluaran dalam rentang waktu [dari, sampai), TERMASUK yang
  /// dibatalkan — halaman Pengeluaran owner menampilkannya berlabel dan
  /// tidak menghitungnya. Terbaru dulu.
  Stream<List<Expense>> watchExpensesInRange(DateTime dari, DateTime sampai) {
    return (select(expenses)
          ..where((e) =>
              e.createdAt.isBiggerOrEqualValue(dari) &
              e.createdAt.isSmallerThanValue(sampai))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  Future<void> addExpense({
    required String? shiftId,
    required String userId,
    required String description,
    required int amount,
    String category = 'bahan_baku',
    int qty = 1,
  }) async {
    await into(expenses).insert(
      ExpensesCompanion(
        id: Value(newUuid()),
        shiftId: Value(shiftId),
        userId: Value(userId),
        userName: Value(await usernameAkun(userId)),
        description: Value(description),
        amount: Value(amount),
        category: Value(category),
        qty: Value(qty),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Batalkan pengeluaran. Barisnya TIDAK dihapus — `deletedAt` diisi
  /// (supaya keluar dari semua total), dicatat siapa dan kenapa, dan disimpan
  /// selamanya. Siapa yang boleh dan kapan PIN owner diperlukan diputuskan
  /// `ExpenseRepository.batalkanPengeluaran`; pemanggil lain WAJIB lewat sana.
  Future<void> batalkanPengeluaran(
    String id, {
    required String olehUserId,
    required String alasan,
  }) async {
    final sekarang = DateTime.now();
    final diubah = await (update(expenses)
          ..where((e) => e.id.equals(id) & e.deletedAt.isNull()))
        .write(ExpensesCompanion(
      deletedAt: Value(sekarang),
      cancelledByUserId: Value(olehUserId),
      cancelledByName: Value(await usernameAkun(olehUserId)),
      cancelReason: Value(alasan),
      updatedAt: Value(sekarang),
      syncStatus: const Value('pending'),
    ));
    if (diubah == 0) {
      throw StateError('Pengeluaran tidak ditemukan atau sudah dibatalkan.');
    }
  }

  /// Batalkan transaksi beserta itemnya, dalam satu transaction.
  ///
  /// Barisnya TIDAK dihapus — `deletedAt` diisi (supaya keluar dari semua
  /// total), dicatat siapa dan kenapa, dan disimpan selamanya. Siapa yang
  /// boleh membatalkan dan kapan PIN owner diperlukan diputuskan
  /// `SalesRepository.batalkanTransaksi`; pemanggil lain WAJIB lewat sana.
  Future<void> batalkanTransaksi(
    String transactionId, {
    required String olehUserId,
    required String alasan,
  }) async {
    final sekarang = DateTime.now();
    final namaPembatal = await usernameAkun(olehUserId);
    await transaction(() async {
      final diubah = await (update(transactions)
            ..where((t) => t.id.equals(transactionId) & t.deletedAt.isNull()))
          .write(TransactionsCompanion(
        deletedAt: Value(sekarang),
        cancelledByUserId: Value(olehUserId),
        cancelledByName: Value(namaPembatal),
        cancelReason: Value(alasan),
        updatedAt: Value(sekarang),
        syncStatus: const Value('pending'),
      ));
      if (diubah == 0) {
        throw StateError('Transaksi tidak ditemukan atau sudah dibatalkan.');
      }

      await (update(transactionItems)
            ..where((ti) => ti.transactionId.equals(transactionId)))
          .write(TransactionItemsCompanion(
        deletedAt: Value(sekarang),
        updatedAt: Value(sekarang),
        syncStatus: const Value('pending'),
      ));
    });
  }

  /// Shifts milik seorang user di active business, terurut terbaru di atas
  Future<List<Shift>> getShiftsByUser(String userId) async {
    return (select(shifts)
          ..where((s) =>
              s.userId.equals(userId) &
              s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();
  }

  /// Shift beserta nama kasirnya, terbaru dulu.
  ///
  /// [userId] null berarti SEMUA kasir — itulah yang dilihat owner di halaman
  /// Pengeluaran. Diisi berarti dibatasi ke satu orang, yang dipakai kasir
  /// untuk melihat riwayatnya sendiri.
  Future<List<ShiftEntry>> getShiftsWithUser({String? userId}) async {
    final kueri = select(shifts).join([
      innerJoin(users, users.id.equalsExp(shifts.userId)),
    ])
      ..where(shifts.deletedAt.isNull());

    if (userId != null) {
      kueri.where(shifts.userId.equals(userId));
    }
    kueri.orderBy([OrderingTerm.desc(shifts.startAt)]);

    final baris = await kueri.get();
    return baris
        .map((b) => ShiftEntry(
              shift: b.readTable(shifts),
              // Salinan nama saat shift dibuka (v35); shift dari HP lama
              // tanpa salinan memakai nama akun saat ini.
              username: b.readTable(shifts).userName ??
                  b.readTable(users).username,
            ))
        .toList();
  }

  /// Pengeluaran milik sekumpulan shift sekaligus, dikelompokkan per shift.
  ///
  /// Dulu tiap kartu riwayat memuat pengeluarannya sendiri-sendiri,
  /// dan baru saat kartunya dibuka. Akibatnya halaman tidak pernah tahu shift
  /// mana yang kosong, sehingga shift tanpa pengeluaran pun ikut terdaftar.
  /// Satu kueri di depan menyelesaikan keduanya.
  ///
  /// Shift yang tidak punya pengeluaran TIDAK muncul sebagai kunci.
  /// [termasukBatal] untuk halaman Pengeluaran — lihat [watchExpensesByShift].
  Future<Map<String, List<Expense>>> getExpensesForShifts(
    List<String> shiftIds, {
    bool termasukBatal = false,
  }) async {
    if (shiftIds.isEmpty) return {};

    final baris = await (select(expenses)
          ..where((e) =>
              e.shiftId.isIn(shiftIds) &
              (termasukBatal ? const Constant(true) : e.deletedAt.isNull()))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();

    final hasil = <String, List<Expense>>{};
    for (final e in baris) {
      // Disaring `isIn(shiftIds)` di atas, jadi shift-nya pasti ada.
      hasil.putIfAbsent(e.shiftId!, () => []).add(e);
    }
    return hasil;
  }

  // ---- REPORTS ----

  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return (select(transactions)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.createdAt.isBiggerOrEqualValue(startDate) &
              t.createdAt.isSmallerThanValue(endDate))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}

// ---- DB CONNECTION ----

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kasir_app.sqlite'));
    return NativeDatabase(file);
  });
}
