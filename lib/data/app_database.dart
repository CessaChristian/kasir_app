import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/models/sale_line.dart';
import '../data/models/top_product.dart';
import '../shared/auth/session_manager.dart';
import 'uuid_helper.dart';

part 'app_database.g.dart';
part 'models/report_models.dart';

/// Hook yang di-set dari luar (db.dart) untuk menghindari circular import.
/// BusinessContext imports app_database.dart, sehingga app_database.dart
/// tidak boleh import business_context.dart secara langsung.
///
/// Usage dari db.dart:
///   AppDatabase.activeBusinessIdProvider = () => BusinessContext.instance.activeBusinessId;
///
/// Usage dari tests:
///   AppDatabase.activeBusinessIdProvider = () => testBusinessId;
String? Function()? _activeBusinessIdProvider;

/// =======================
/// TABLE: BUSINESSES (new in v10)
/// =======================
class Businesses extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'restaurant_dinein' | 'beverage_grabandgo'
  TextColumn get logoPath => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();

  // Sync-friendly columns (per spec §5.1.6)
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  // SQLite tidak punya tipe ENUM, jadi nilai yang sah dijaga lewat CHECK
  // (NEW in v12). Tanpa ini kolom TEXT menerima salah ketik apa pun —
  // yang benar-benar pernah terjadi pada transactions.order_type.
  @override
  List<String> get customConstraints => [
        "CHECK (type IN ('restaurant_dinein', 'beverage_grabandgo'))",
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: USER_BUSINESS_ROLES (many-to-many, new in v10)
/// =======================
class UserBusinessRoles extends Table {
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get role => text()(); // 'owner' | 'cashier' — dijaga CHECK di v12
  DateTimeColumn get assignedAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Sync-friendly
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  List<String> get customConstraints => [
        "CHECK (role IN ('owner', 'cashier'))",
      ];

  @override
  Set<Column> get primaryKey => {userId, businessId};
}

/// =======================
/// TABLE: CATEGORIES (modified in v10 — add business_id + sync fields)
/// =======================
class Categories extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10
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
  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10
  TextColumn get name => text()();
  IntColumn get price => integer()();
  TextColumn get barcode => text().nullable()();

  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();

  BoolColumn get trackStock =>
      boolean().withDefault(const Constant(false))();
  IntColumn get stock => integer().nullable()();

  BoolColumn get hasSpicyOption =>
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

  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  IntColumn get total => integer()();
  TextColumn get paymentMethod => text()();
  IntColumn get cashReceived => integer().nullable()();
  IntColumn get change => integer().nullable()();

  TextColumn get cashierUserId => text().nullable()();
  TextColumn get shiftId => text().nullable()();

  TextColumn get orderType =>
      text().withDefault(const Constant('dine_in'))();

  // Sync-friendly (NEW in v10)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  // NEW in v12. Kolom order_type pernah tercemar 163 baris bernilai
  // 'takeaway' (tanpa garis bawah) dari penyuntikan data langsung, dan
  // seluruhnya terhitung sebagai Dine In di laporan tanpa error apa pun.
  @override
  List<String> get customConstraints => [
        "CHECK (payment_method IN ('cash', 'qris'))",
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
  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10 (denormalized untuk performa)
  TextColumn get transactionId => text()();
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

  // Sync-friendly (NEW in v10 — siap untuk Phase 2 sync)
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
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
  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10
  TextColumn get userId => text().references(Users, #id)();
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
class UserPermissions extends Table {
  TextColumn get userId => text()();
  TextColumn get permissionCode => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE',
        'FOREIGN KEY(permission_code) REFERENCES permissions(code) ON DELETE CASCADE',
      ];

  @override
  Set<Column> get primaryKey => {userId, permissionCode};
}

/// =======================
/// TABLE: EXPENSES (modified in v10 — add business_id + sync fields + updated_by_user_id)
/// =======================
class Expenses extends Table {
  TextColumn get id => text().clientDefault(() => newUuid())();
  TextColumn get businessId =>
      text().references(Businesses, #id)(); // NEW in v10
  TextColumn get shiftId => text().references(Shifts, #id)();
  @ReferenceName('createdExpensesRefs')
  TextColumn get userId => text().references(Users, #id)(); // creator
  @ReferenceName('updatedExpensesRefs')
  TextColumn get updatedByUserId =>
      text().nullable().references(Users, #id)(); // NEW in v10 — track edit
  TextColumn get description => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

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
  Businesses,           // NEW in v10
  UserBusinessRoles,    // NEW in v10
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  // ---- BusinessContext bridge (no circular import) ----

  /// Set dari db.dart setelah BusinessContext tersedia.
  /// Atau di-override dalam tests:
  ///   AppDatabase.activeBusinessIdProvider = () => 'test-biz-id';
  static set activeBusinessIdProvider(String? Function()? fn) {
    _activeBusinessIdProvider = fn;
  }

  /// True jika provider sudah di-wire (dipakai test untuk memastikan
  /// mengakses `db` otomatis melakukan wiring).
  static bool get hasActiveBusinessProvider =>
      _activeBusinessIdProvider != null;

  /// Ambil active business ID. Throws [StateError] jika provider belum di-set
  /// atau tidak ada active business.
  static String _requireActiveBusinessId() {
    final provider = _activeBusinessIdProvider;
    if (provider == null) {
      throw StateError(
        'AppDatabase.activeBusinessIdProvider belum di-set. '
        'Pastikan db.dart sudah wired BusinessContext.',
      );
    }
    final id = provider();
    if (id == null) {
      throw StateError(
        'Tidak ada active business. Login dan pilih business terlebih dahulu.',
      );
    }
    return id;
  }

  /// Versi nullable — untuk watch/query yang boleh return empty stream
  /// ketika belum ada active business.
  static String? _getActiveBusinessId() {
    return _activeBusinessIdProvider?.call();
  }

  @override
  int get schemaVersion => 12;

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

            // Recreate semua (termasuk Businesses + UserBusinessRoles)
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
            await m.alterTable(TableMigration(transactions));
            await m.alterTable(TableMigration(users));
            await m.alterTable(TableMigration(userBusinessRoles));
            await m.alterTable(TableMigration(businesses));
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

  Future<void> _seedPermissions() async {
    const permissionsData = [
      {
        'code': 'open_close_shift',
        'name': 'Open/Close Shift',
        'description': 'Ability to start and end work shifts'
      },
      {
        'code': 'create_transaction',
        'name': 'Create Transaction',
        'description': 'Ability to process sales transactions'
      },
      {
        'code': 'view_history',
        'name': 'View Transaction History',
        'description': 'Ability to view past transactions'
      },
      {
        'code': 'view_report',
        'name': 'View Reports',
        'description': 'Ability to view sales reports and analytics'
      },
      {
        'code': 'manage_products',
        'name': 'Manage Products',
        'description': 'Ability to add, edit, and delete products'
      },
      {
        'code': 'manage_cashiers',
        'name': 'Manage Cashiers',
        'description': 'Ability to add, edit, and manage cashier accounts'
      },
      {
        'code': 'edit_own_expense',
        'name': 'Edit Own Expense',
        'description': 'Ability to edit expenses created by self'
      },
      {
        'code': 'edit_any_expense',
        'name': 'Edit Any Expense',
        'description': 'Ability to edit any expense (owner override)'
      },
      {
        'code': 'delete_own_transaction',
        'name': 'Delete Own Transaction',
        'description': 'Ability to soft-delete transactions created by self'
      },
      {
        'code': 'delete_any_transaction',
        'name': 'Delete Any Transaction',
        'description': 'Ability to soft-delete any transaction (owner override)'
      },
      {
        'code': 'view_shift_reports',
        'name': 'View Shift Reports',
        'description': 'Ability to view shift reports page'
      },
      {
        'code': 'view_all_shifts',
        'name': 'View All Shifts',
        'description': 'Ability to view shift data from all users'
      },
      {
        'code': 'manage_business',
        'name': 'Manage Business',
        'description': 'Ability to create or edit business settings'
      },
      {
        'code': 'switch_business',
        'name': 'Switch Business',
        'description': 'Ability to switch active business from UI'
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

  Future<void> resetDatabase() async {
    await transaction(() async {
      await delete(transactionItems).go();
      await delete(transactions).go();
      await delete(products).go();
      await delete(categories).go();
    });
  }

  // ---- CATEGORIES ----

  Stream<List<Category>> watchCategories() {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return const Stream.empty();
    return (select(categories)
          ..where((t) =>
              t.businessId.equals(businessId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<void> upsertCategory({
    required String id,
    required String name,
    int? iconCodepoint,
  }) async {
    final businessId = _requireActiveBusinessId();
    SessionManager.instance.requirePermission('manage_products');
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion(
        id: Value(id),
        businessId: Value(businessId),
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
    final businessId = _getActiveBusinessId();
    if (businessId == null) return const Stream.empty();
    return (select(products)
          ..where((p) =>
              p.businessId.equals(businessId) & p.deletedAt.isNull()))
        .watch();
  }

  Future<void> upsertProduct({
    required String id,
    required String name,
    required int price,
    String? barcode,
    String? categoryId,
    required bool trackStock,
    int? stock,
    required bool hasSpicyOption,
    String? imagePath,
  }) async {
    final businessId = _requireActiveBusinessId();
    SessionManager.instance.requirePermission('manage_products');
    final data = ProductsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      price: Value(price),
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      trackStock: Value(trackStock),
      stock: Value(trackStock ? stock : null),
      hasSpicyOption: Value(hasSpicyOption),
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

  // ---- SALES ----

  Future<void> createSale({
    required String transactionId,
    required String invoiceNo,
    required List<SaleLine> lines,
    required String paymentMethod,
    required String orderType,
    int? cashReceived,
    String? cashierUserId,
    String? shiftId,
  }) async {
    final businessId = _requireActiveBusinessId();
    // M-A: Defense-in-depth — selain UI yang sudah hide tombol "Kasir",
    // DB layer juga reject jika permission tidak ada.
    SessionManager.instance.requirePermission('create_transaction');

    if (lines.isEmpty) throw ArgumentError('Cart kosong');

    final total = lines.fold<int>(0, (s, l) => s + l.subtotal);

    if (paymentMethod == 'cash') {
      if (cashReceived == null) {
        throw ArgumentError('Cash received wajib diisi untuk pembayaran cash');
      }
      if (cashReceived < total) {
        throw ArgumentError('Uang diterima kurang');
      }
    }

    final changeAmount =
        paymentMethod == 'cash' ? (cashReceived! - total) : null;

    await transaction(() async {
      await _validateAndUpdateStock(lines);

      await into(transactions).insert(
        TransactionsCompanion(
          id: Value(transactionId),
          invoiceNo: Value(invoiceNo),
          businessId: Value(businessId),
          total: Value(total),
          paymentMethod: Value(paymentMethod),
          cashReceived: Value(cashReceived),
          change: Value(changeAmount),
          cashierUserId: Value(cashierUserId),
          shiftId: Value(shiftId),
          orderType: Value(orderType),
          syncStatus: const Value('pending'),
        ),
      );

      await _insertTransactionItems(transactionId, businessId, lines);
    });
  }

  // Validate + update stock atomically per produk menggunakan single UPDATE statement.
  // rowsAffected == 0 berarti stok tidak cukup (concurrent update atau stok NULL).
  Future<void> _validateAndUpdateStock(List<SaleLine> lines) async {
    for (final line in lines) {
      if (!line.trackStock) continue;

      // Filter deletedAt WAJIB: sejak produk memakai soft delete, barisnya
      // tetap ada setelah dihapus. Tanpa filter ini produk yang sudah dihapus
      // masih bisa terjual.
      final product = await (select(products)
            ..where((t) => t.id.equals(line.productId) & t.deletedAt.isNull()))
          .getSingleOrNull();

      if (product == null) {
        throw StateError(
          '"${line.productName}" sudah tidak tersedia. '
          'Hapus produk ini dari keranjang sebelum melanjutkan.',
        );
      }

      final updated = await customUpdate(
        'UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?',
        variables: [
          Variable.withInt(line.qty),
          Variable.withString(line.productId),
          Variable.withInt(line.qty),
        ],
        updates: {products},
      );

      if (updated == 0) {
        throw StateError('Stok tidak cukup untuk "${product.name}"');
      }
    }
  }

  Future<void> _insertTransactionItems(
    String transactionId,
    String businessId, // already fetched from BusinessContext by createSale
    List<SaleLine> lines,
  ) async {
    for (final line in lines) {
      final itemId = newUuid();

      await into(transactionItems).insert(
        TransactionItemsCompanion(
          id: Value(itemId),
          businessId: Value(businessId),
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

  Stream<List<Transaction>> watchTransactions() {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return const Stream.empty();
    return (select(transactions)
          ..where((t) =>
              t.businessId.equals(businessId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<TransactionItem>> getTransactionItems(
      String transactionId) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];
    return (select(transactionItems)
          ..where((t) =>
              t.transactionId.equals(transactionId) &
              t.businessId.equals(businessId) &
              t.deletedAt.isNull()))
        .get();
  }

  /// C1: Batch fetch — hindari N+1 query saat export laporan.
  /// Return Map keyed by transactionId untuk lookup in-memory.
  Future<Map<String, List<TransactionItem>>> getTransactionItemsForIds(
      List<String> transactionIds) async {
    if (transactionIds.isEmpty) return {};

    final businessId = _getActiveBusinessId();
    if (businessId == null) return {};

    final items = await (select(transactionItems)
          ..where((t) =>
              t.transactionId.isIn(transactionIds) &
              t.businessId.equals(businessId) &
              t.deletedAt.isNull()))
        .get();

    final result = <String, List<TransactionItem>>{};
    for (final id in transactionIds) {
      result[id] = [];
    }
    for (final item in items) {
      result.putIfAbsent(item.transactionId, () => []).add(item);
    }
    return result;
  }

  // ---- EXPENSES ----

  Stream<List<Expense>> watchExpensesByShift(String shiftId) {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return const Stream.empty();
    return (select(expenses)
          ..where((e) =>
              e.shiftId.equals(shiftId) &
              e.businessId.equals(businessId) &
              e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  Future<void> addExpense({
    required String shiftId,
    required String userId,
    required String description,
    required int amount,
  }) async {
    final businessId = _requireActiveBusinessId();
    await into(expenses).insert(
      ExpensesCompanion(
        id: Value(newUuid()),
        businessId: Value(businessId),
        shiftId: Value(shiftId),
        userId: Value(userId),
        description: Value(description),
        amount: Value(amount),
        syncStatus: const Value('pending'),
      ),
    );
  }

  /// Soft delete pengeluaran — lihat catatan di [deleteCategory].
  Future<void> deleteExpense(String id) async {
    final now = DateTime.now();
    await (update(expenses)..where((e) => e.id.equals(id)))
        .write(ExpensesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      updatedByUserId: Value(SessionManager.instance.currentUserId),
      syncStatus: const Value('pending'),
    ));
  }

  /// Update expense. Hanya update amount + description.
  /// Caller bertanggung jawab validasi permission sebelum call ini.
  Future<void> updateExpense({
    required String id,
    required int amount,
    required String description,
  }) async {
    final businessId = _requireActiveBusinessId();
    await (update(expenses)..where((e) =>
      e.id.equals(id) & e.businessId.equals(businessId)
    )).write(ExpensesCompanion(
      amount: Value(amount),
      description: Value(description),
      updatedByUserId: Value(SessionManager.instance.currentUserId),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  /// Update profil business aktif (nama, alamat, telepon).
  /// Caller WAJIB validasi permission manage_business sebelum call.
  /// Update profil business (aktif maupun tidak) — dipakai page Business.
  /// Nama business TIDAK bisa diubah (hardcode dari kode, spec REVISI 2 D5).
  /// Field null = tidak diubah; `logoPathSet: true` + `logoPath: null`
  /// artinya hapus logo.
  Future<void> updateBusiness({
    required String id,
    String? address,
    String? phone,
    String? logoPath,
    bool logoPathSet = false,
  }) async {
    SessionManager.instance.requireCurrentPermission('manage_business');
    await (update(businesses)..where((b) => b.id.equals(id)))
        .write(BusinessesCompanion(
      address: address != null ? Value(address) : const Value.absent(),
      phone: phone != null ? Value(phone) : const Value.absent(),
      logoPath: logoPathSet ? Value(logoPath) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  /// Soft-delete transaksi + reverse stok (transactional).
  /// Caller WAJIB validasi permission sebelum call.
  Future<void> softDeleteTransaction(String transactionId) async {
    final businessId = _requireActiveBusinessId();

    await transaction(() async {
      // 1. Soft delete transaction header
      await (update(transactions)..where((t) =>
        t.id.equals(transactionId) & t.businessId.equals(businessId)
      )).write(TransactionsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));

      // 2. Soft delete transaction items
      await (update(transactionItems)..where((ti) =>
        ti.transactionId.equals(transactionId) & ti.businessId.equals(businessId)
      )).write(TransactionItemsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));

      // 3. Fetch items (WITHOUT deleted filter — we just set deletedAt above)
      final items = await (select(transactionItems)..where((ti) =>
        ti.transactionId.equals(transactionId)
      )).get();

      // 4. Reverse stock movements (kembalikan stok produk)
      for (final item in items) {
        final prod = await (select(products)
          ..where((p) => p.id.equals(item.productId) & p.deletedAt.isNull())
          ..limit(1)).getSingleOrNull();

        if (prod != null && prod.trackStock && prod.stock != null) {
          await (update(products)..where((p) => p.id.equals(item.productId))).write(
            ProductsCompanion(
              stock: Value(prod.stock! + item.qty),
              updatedAt: Value(DateTime.now()),
              syncStatus: const Value('pending'),
            ),
          );
        }
      }
    });
  }

  /// Shifts milik seorang user di active business, terurut terbaru di atas
  Future<List<Shift>> getShiftsByUser(String userId) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];
    return (select(shifts)
          ..where((s) =>
              s.userId.equals(userId) &
              s.businessId.equals(businessId) &
              s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();
  }

  Future<List<Expense>> getExpensesByShift(String shiftId) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];
    return (select(expenses)
          ..where((e) =>
              e.shiftId.equals(shiftId) &
              e.businessId.equals(businessId) &
              e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();
  }

  /// Semua pengeluaran dengan info user — untuk halaman owner, di-scope ke active business
  Future<List<ExpenseEntry>> getAllExpensesForOwner({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];

    final query = select(expenses).join([
      innerJoin(users, users.id.equalsExp(expenses.userId)),
    ]);

    query.where(expenses.businessId.equals(businessId));
    query.where(expenses.deletedAt.isNull());

    if (startDate != null) {
      query.where(expenses.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(expenses.createdAt.isSmallerThanValue(endDate));
    }
    query.orderBy([OrderingTerm.desc(expenses.createdAt)]);

    final rows = await query.get();
    return rows.map((row) {
      return ExpenseEntry(
        expense: row.readTable(expenses),
        username: row.readTable(users).username,
      );
    }).toList();
  }

  Future<int> _getTotalExpensesByDateRange(
      DateTime startDate, DateTime endDate) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return 0;
    final result = await (select(expenses)
          ..where((e) =>
              e.businessId.equals(businessId) &
              e.deletedAt.isNull() &
              e.createdAt.isBiggerOrEqualValue(startDate) &
              e.createdAt.isSmallerThanValue(endDate)))
        .get();
    return result.fold<int>(0, (sum, e) => sum + e.amount);
  }

  // ---- REPORTS ----

  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];
    return (select(transactions)
          ..where((t) =>
              t.businessId.equals(businessId) &
              t.deletedAt.isNull() &
              t.createdAt.isBiggerOrEqualValue(startDate) &
              t.createdAt.isSmallerThanValue(endDate))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<ReportSummary> getReportSummary(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final dayTransactions =
        await getTransactionsByDateRange(startOfDay, endOfDay);
    final totalExpenses =
        await _getTotalExpensesByDateRange(startOfDay, endOfDay);

    final totalOrders = dayTransactions.length;
    final totalIncome =
        dayTransactions.fold<int>(0, (sum, tx) => sum + tx.total);

    final cashTx =
        dayTransactions.where((tx) => tx.paymentMethod == 'cash').toList();
    final qrisTx =
        dayTransactions.where((tx) => tx.paymentMethod == 'qris').toList();

    final dineInOrders = dayTransactions
        .where((tx) => tx.orderType == 'dine_in')
        .length;
    final takeAwayOrders = dayTransactions
        .where((tx) => tx.orderType == 'take_away')
        .length;
    final deliveryOrders = dayTransactions
        .where((tx) => tx.orderType == 'delivery')
        .length;

    final topProducts =
        await getTopSellingProducts(startOfDay, endOfDay);

    return ReportSummary(
      date: date,
      totalOrders: totalOrders,
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      cashOrders: cashTx.length,
      cashTotal: cashTx.fold<int>(0, (sum, tx) => sum + tx.total),
      qrisOrders: qrisTx.length,
      qrisTotal: qrisTx.fold<int>(0, (sum, tx) => sum + tx.total),
      dineInOrders: dineInOrders,
      takeAwayOrders: takeAwayOrders,
      deliveryOrders: deliveryOrders,
      transactions: dayTransactions,
      topProducts: topProducts,
    );
  }

  Future<List<TopProduct>> getTopSellingProducts(
    DateTime startDate,
    DateTime endDate, {
    int limit = 5,
  }) async {
    final businessId = _getActiveBusinessId();
    if (businessId == null) return [];

    final startEpoch = startDate.millisecondsSinceEpoch ~/ 1000;
    final endEpoch = endDate.millisecondsSinceEpoch ~/ 1000;

    final result = await customSelect(
      '''
      SELECT
        ti.product_name,
        SUM(ti.qty) as total_qty,
        SUM(ti.subtotal) as total_sales
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.created_at BETWEEN ? AND ?
        AND t.business_id = ?
        AND t.deleted_at IS NULL
        AND ti.deleted_at IS NULL
      GROUP BY ti.product_name
      ORDER BY total_qty DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withInt(startEpoch),
        Variable.withInt(endEpoch),
        Variable.withString(businessId),
        Variable.withInt(limit)
      ],
      readsFrom: {transactionItems, transactions},
    ).get();

    return result.map((row) {
      return TopProduct(
        productName: row.read<String>('product_name'),
        totalQty: row.read<int>('total_qty'),
        totalSales: row.read<int>('total_sales'),
      );
    }).toList();
  }

  Future<List<EmployeeReportSummary>> getEmployeeReportSummary(
      DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final dayTransactions =
        await getTransactionsByDateRange(startOfDay, endOfDay);

    final userIds = dayTransactions
        .where((tx) => tx.cashierUserId != null)
        .map((tx) => tx.cashierUserId!)
        .toSet()
        .toList();

    if (userIds.isEmpty) return [];

    return _buildEmployeeReports(
      txList: dayTransactions,
      userIds: userIds,
      expenseStartDate: startOfDay,
      expenseEndDate: endOfDay,
      shiftStartDate: startOfDay,
      shiftEndDate: endOfDay,
    );
  }

  // Helper yang bekerja dengan items yang sudah di-fetch (tidak async)
  List<TopProduct> _aggregateTopProducts(
      List<TransactionItem> items, {int limit = 5}) {
    final Map<String, TopProduct> productMap = {};
    for (final item in items) {
      final existing = productMap[item.productName];
      if (existing != null) {
        productMap[item.productName] = TopProduct(
          productName: item.productName,
          totalQty: existing.totalQty + item.qty,
          totalSales: existing.totalSales + item.subtotal,
        );
      } else {
        productMap[item.productName] = TopProduct(
          productName: item.productName,
          totalQty: item.qty,
          totalSales: item.subtotal,
        );
      }
    }
    return (productMap.values.toList()
          ..sort((a, b) => b.totalQty.compareTo(a.totalQty)))
        .take(limit)
        .toList();
  }

  Future<ReportSummary> getMonthlyReportSummary(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final monthTx = await getTransactionsByDateRange(startOfMonth, endOfMonth);
    final totalExpenses =
        await _getTotalExpensesByDateRange(startOfMonth, endOfMonth);

    final cashTx =
        monthTx.where((tx) => tx.paymentMethod == 'cash').toList();
    final qrisTx =
        monthTx.where((tx) => tx.paymentMethod == 'qris').toList();

    final dineInOrders =
        monthTx.where((tx) => tx.orderType == 'dine_in').length;
    final takeAwayOrders =
        monthTx.where((tx) => tx.orderType == 'take_away').length;
    final deliveryOrders =
        monthTx.where((tx) => tx.orderType == 'delivery').length;

    final topProducts =
        await getTopSellingProducts(startOfMonth, endOfMonth);

    return ReportSummary(
      date: startOfMonth,
      totalOrders: monthTx.length,
      totalIncome: monthTx.fold<int>(0, (sum, tx) => sum + tx.total),
      totalExpenses: totalExpenses,
      cashOrders: cashTx.length,
      cashTotal: cashTx.fold<int>(0, (sum, tx) => sum + tx.total),
      qrisOrders: qrisTx.length,
      qrisTotal: qrisTx.fold<int>(0, (sum, tx) => sum + tx.total),
      dineInOrders: dineInOrders,
      takeAwayOrders: takeAwayOrders,
      deliveryOrders: deliveryOrders,
      transactions: monthTx,
      topProducts: topProducts,
    );
  }

  Future<List<DailyTrend>> getDailyTrends(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);
    final daysInMonth = endOfMonth.difference(startOfMonth).inDays;

    final monthTx =
        await getTransactionsByDateRange(startOfMonth, endOfMonth);

    final List<DailyTrend> trends = [];
    for (int day = 1; day <= daysInMonth; day++) {
      final dayTx = monthTx.where((tx) {
        return tx.createdAt.year == year &&
            tx.createdAt.month == month &&
            tx.createdAt.day == day;
      }).toList();

      trends.add(DailyTrend(
        date: DateTime(year, month, day),
        orders: dayTx.length,
        income: dayTx.fold<int>(0, (sum, tx) => sum + tx.total),
      ));
    }
    return trends;
  }

  Future<List<EmployeeReportSummary>> getEmployeeReportSummaryForRange(
      DateTime startDate, DateTime endDate) async {
    final rangeTx = await getTransactionsByDateRange(startDate, endDate);

    final userIds = rangeTx
        .where((tx) => tx.cashierUserId != null)
        .map((tx) => tx.cashierUserId!)
        .toSet()
        .toList();

    if (userIds.isEmpty) return [];

    return _buildEmployeeReports(
      txList: rangeTx,
      userIds: userIds,
      expenseStartDate: startDate,
      expenseEndDate: endDate,
      shiftStartDate: startDate,
      shiftEndDate: endDate,
    );
  }

  /// Core builder: 5 queries total untuk semua user (bukan N queries per user)
  Future<List<EmployeeReportSummary>> _buildEmployeeReports({
    required List<Transaction> txList,
    required List<String> userIds,
    required DateTime expenseStartDate,
    required DateTime expenseEndDate,
    required DateTime shiftStartDate,
    required DateTime shiftEndDate,
  }) async {
    // Query 1: Semua user sekaligus
    final allUsers = await (select(users)
          ..where((u) => u.id.isIn(userIds)))
        .get();
    final userMap = {for (final u in allUsers) u.id: u};

    // Query 2: Semua shift sekaligus
    final allShifts = await (select(shifts)
          ..where((s) =>
              s.userId.isIn(userIds) &
              s.startAt.isBiggerOrEqualValue(shiftStartDate) &
              s.startAt.isSmallerThanValue(shiftEndDate))
          ..orderBy([(s) => OrderingTerm.asc(s.startAt)]))
        .get();
    final shiftMap = {for (final s in allShifts) s.id: s};
    final shiftsByUser = <String, List<Shift>>{};
    for (final s in allShifts) {
      shiftsByUser.putIfAbsent(s.userId, () => []).add(s);
    }

    // Query 3: Semua expenses per shift sekaligus
    final allShiftIds = allShifts.map((s) => s.id).toList();
    final allShiftExpenses = allShiftIds.isNotEmpty
        ? await (select(expenses)
              ..where((e) =>
                  e.shiftId.isIn(allShiftIds) & e.deletedAt.isNull()))
            .get()
        : <Expense>[];
    final expensesByShift = <String, List<Expense>>{};
    for (final e in allShiftExpenses) {
      expensesByShift.putIfAbsent(e.shiftId, () => []).add(e);
    }

    // Query 4: Semua expenses per user sekaligus (untuk total)
    final allUserExpenses = await (select(expenses)
          ..where((e) =>
              e.userId.isIn(userIds) &
              e.deletedAt.isNull() &
              e.createdAt.isBiggerOrEqualValue(expenseStartDate) &
              e.createdAt.isSmallerThanValue(expenseEndDate)))
        .get();
    final totalExpensesByUser = <String, int>{};
    for (final e in allUserExpenses) {
      totalExpensesByUser[e.userId] =
          (totalExpensesByUser[e.userId] ?? 0) + e.amount;
    }

    // Query 5: Semua transaction items sekaligus (untuk top products)
    final txIds = txList.map((tx) => tx.id).toList();
    final allItems = txIds.isNotEmpty
        ? await (select(transactionItems)
              ..where((ti) => ti.transactionId.isIn(txIds)))
            .get()
        : <TransactionItem>[];
    final itemsByTxId = <String, List<TransactionItem>>{};
    for (final item in allItems) {
      itemsByTxId.putIfAbsent(item.transactionId, () => []).add(item);
    }

    // Build reports in-memory — tidak ada query lagi di sini
    final reports = <EmployeeReportSummary>[];

    for (final userId in userIds) {
      final user = userMap[userId];
      if (user == null) continue;

      final userTx =
          txList.where((tx) => tx.cashierUserId == userId).toList();
      final cashTx =
          userTx.where((tx) => tx.paymentMethod == 'cash').toList();
      final qrisTx =
          userTx.where((tx) => tx.paymentMethod == 'qris').toList();
      final totalExpenses = totalExpensesByUser[userId] ?? 0;

      final userShiftIds = userTx
          .where((tx) => tx.shiftId != null)
          .map((tx) => tx.shiftId!)
          .toSet();

      final shiftInfos = <ShiftInfo>[];
      for (final shiftId in userShiftIds) {
        final shift = shiftMap[shiftId];
        if (shift == null) continue;
        final shiftTx = userTx.where((tx) => tx.shiftId == shiftId).toList();
        final shiftExpTotal = (expensesByShift[shiftId] ?? [])
            .fold<int>(0, (s, e) => s + e.amount);
        shiftInfos.add(ShiftInfo(
          shiftId: shiftId,
          startAt: shift.startAt,
          endAt: shift.endAt,
          transactionCount: shiftTx.length,
          totalIncome: shiftTx.fold<int>(0, (s, tx) => s + tx.total),
          totalExpenses: shiftExpTotal,
        ));
      }
      shiftInfos.sort((a, b) => a.startAt.compareTo(b.startAt));

      // Hitung top products dari pre-fetched items
      final userItems = userTx
          .expand((tx) => itemsByTxId[tx.id] ?? <TransactionItem>[])
          .toList();
      final topProducts = _aggregateTopProducts(userItems);

      reports.add(EmployeeReportSummary(
        userId: userId,
        username: user.username,
        totalTransactions: userTx.length,
        totalIncome: userTx.fold<int>(0, (s, tx) => s + tx.total),
        totalExpenses: totalExpenses,
        cashOrders: cashTx.length,
        cashTotal: cashTx.fold<int>(0, (s, tx) => s + tx.total),
        qrisOrders: qrisTx.length,
        qrisTotal: qrisTx.fold<int>(0, (s, tx) => s + tx.total),
        shifts: shiftInfos,
        transactions: userTx,
        topProducts: topProducts,
      ));
    }

    reports.sort((a, b) => b.totalIncome.compareTo(a.totalIncome));
    return reports;
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

Future<void> deleteDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'kasir_app.sqlite'));
  if (await file.exists()) {
    await file.delete();
  }
}
