import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/models/sale_line.dart';
import '../data/models/top_product.dart';
import '../shared/auth/session_manager.dart';

part 'app_database.g.dart';
part 'models/report_models.dart';

/// =======================
/// TABLE: CATEGORIES
/// =======================
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get iconCodepoint => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: PRODUCTS
/// =======================
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get price => integer()();
  TextColumn get barcode => text().nullable()();

  // Added in v4
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();

  BoolColumn get trackStock =>
      boolean().withDefault(const Constant(false))();
  IntColumn get stock => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Added in v7
  BoolColumn get hasSpicyOption =>
      boolean().withDefault(const Constant(false))();
  TextColumn get imagePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: TRANSACTIONS
/// =======================
class Transactions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get total => integer()();
  TextColumn get paymentMethod => text()();
  IntColumn get cashReceived => integer().nullable()();
  IntColumn get change => integer().nullable()();

  // Added in v5
  TextColumn get cashierUserId => text().nullable()();
  TextColumn get shiftId => text().nullable()();

  // Added in v7: 'dine_in' | 'take_away' | 'delivery'
  TextColumn get orderType =>
      text().withDefault(const Constant('dine_in'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: TRANSACTION_ITEMS
/// =======================
class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text().withDefault(const Constant(''))();

  IntColumn get qty => integer()();
  IntColumn get priceAtSale => integer()();
  IntColumn get subtotal => integer()();

  // Added in v7: catatan keterangan per item (e.g., 'Pedas', 'Extra Pedas')
  TextColumn get notes => text().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE',
      ];

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: USERS
/// =======================
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().unique()();
  TextColumn get pinHash => text()();
  TextColumn get salt => text()();
  TextColumn get role => text()();
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

  // Login rate limiting (S5): mirror dari recovery, dengan exponential backoff.
  IntColumn get loginAttempts =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get loginLockedUntil => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: SHIFTS
/// =======================
class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get startAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endAt => dateTime().nullable()();

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
/// TABLE: EXPENSES (new in v7)
/// =======================
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get description => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

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
        },
        beforeOpen: (details) async {
          if (details.wasCreated || (details.hadUpgrade && details.versionBefore! < 5)) {
            await _seedPermissions();
          }
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
    return (select(categories)
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
      ),
    );
  }

  Future<void> deleteCategory(String id) async {
    SessionManager.instance.requirePermission('manage_products');
    await transaction(() async {
      await (update(products)..where((p) => p.categoryId.equals(id)))
          .write(const ProductsCompanion(categoryId: Value(null)));
      await (delete(categories)..where((t) => t.id.equals(id))).go();
    });
  }

  // ---- PRODUCTS ----

  Stream<List<Product>> watchProducts() {
    return select(products).watch();
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
    SessionManager.instance.requirePermission('manage_products');
    final data = ProductsCompanion(
      id: Value(id),
      name: Value(name),
      price: Value(price),
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      trackStock: Value(trackStock),
      stock: Value(trackStock ? stock : null),
      hasSpicyOption: Value(hasSpicyOption),
      imagePath: Value(imagePath),
    );
    await into(products).insertOnConflictUpdate(data);
  }

  Future<void> deleteProduct(String id) async {
    SessionManager.instance.requirePermission('manage_products');
    await (delete(products)..where((t) => t.id.equals(id))).go();
  }

  // ---- SALES ----

  Future<void> createSale({
    required String transactionId,
    required List<SaleLine> lines,
    required String paymentMethod,
    required String orderType,
    int? cashReceived,
    String? cashierUserId,
    String? shiftId,
  }) async {
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
          total: Value(total),
          paymentMethod: Value(paymentMethod),
          cashReceived: Value(cashReceived),
          change: Value(changeAmount),
          cashierUserId: Value(cashierUserId),
          shiftId: Value(shiftId),
          orderType: Value(orderType),
        ),
      );

      await _insertTransactionItems(transactionId, lines);
    });
  }

  // Validate + update stock atomically per produk menggunakan single UPDATE statement.
  // rowsAffected == 0 berarti stok tidak cukup (concurrent update atau stok NULL).
  Future<void> _validateAndUpdateStock(List<SaleLine> lines) async {
    for (final line in lines) {
      if (!line.trackStock) continue;

      final product = await (select(products)
            ..where((t) => t.id.equals(line.productId)))
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
    List<SaleLine> lines,
  ) async {
    for (final line in lines) {
      final itemId = _generateUniqueId();

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
        ),
      );
    }
  }

  // ---- TRANSACTIONS / HISTORY ----

  Stream<List<Transaction>> watchTransactions() {
    return (select(transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<TransactionItem>> getTransactionItems(
      String transactionId) async {
    return (select(transactionItems)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
  }

  /// C1: Batch fetch — hindari N+1 query saat export laporan.
  /// Return Map keyed by transactionId untuk lookup in-memory.
  Future<Map<String, List<TransactionItem>>> getTransactionItemsForIds(
      List<String> transactionIds) async {
    if (transactionIds.isEmpty) return {};

    final items = await (select(transactionItems)
          ..where((t) => t.transactionId.isIn(transactionIds)))
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
    return (select(expenses)
          ..where((e) => e.shiftId.equals(shiftId))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .watch();
  }

  Future<void> addExpense({
    required String shiftId,
    required String userId,
    required String description,
    required int amount,
  }) async {
    await into(expenses).insert(
      ExpensesCompanion.insert(
        id: _generateUniqueId(),
        shiftId: shiftId,
        userId: userId,
        description: description,
        amount: amount,
      ),
    );
  }

  Future<void> deleteExpense(String id) async {
    await (delete(expenses)..where((e) => e.id.equals(id))).go();
  }

  /// Shifts milik seorang user, terurut terbaru di atas
  Future<List<Shift>> getShiftsByUser(String userId) async {
    return (select(shifts)
          ..where((s) => s.userId.equals(userId))
          ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();
  }

  Future<List<Expense>> getExpensesByShift(String shiftId) async {
    return (select(expenses)
          ..where((e) => e.shiftId.equals(shiftId))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();
  }

  /// Semua pengeluaran dengan info user — untuk halaman owner
  Future<List<ExpenseEntry>> getAllExpensesForOwner({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = select(expenses).join([
      innerJoin(users, users.id.equalsExp(expenses.userId)),
    ]);

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
    final result = await (select(expenses)
          ..where((e) =>
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
    return (select(transactions)
          ..where((t) =>
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
      GROUP BY ti.product_name
      ORDER BY total_qty DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withInt(startEpoch),
        Variable.withInt(endEpoch),
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
              ..where((e) => e.shiftId.isIn(allShiftIds)))
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

// ---- UTILITY ----

// S10: pakai Random.secure() agar ID tidak dapat diprediksi.
final _secureRandom = Random.secure();

String _generateUniqueId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final random = _secureRandom.nextInt(99999).toString().padLeft(5, '0');
  return '${timestamp}_$random';
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
