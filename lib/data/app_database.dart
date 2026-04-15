import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/models/sale_line.dart';
import '../data/models/top_product.dart';

part 'app_database.g.dart';

/// =======================
/// TABLE: CATEGORIES
/// =======================
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// =======================
/// TABLE: PRODUCTS
/// =======================
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get price => integer()(); // simpan rupiah sebagai int
  TextColumn get barcode => text().nullable()();

  // Added in v4
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();

  BoolColumn get trackStock =>
      boolean().withDefault(const Constant(false))();
  IntColumn get stock => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// =======================
/// TABLE: Transaction
/// =======================
class Transactions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get total => integer()(); // total rupiah
  TextColumn get paymentMethod => text()(); // 'cash' atau 'qris'
  IntColumn get cashReceived => integer().nullable()();
  IntColumn get change => integer().nullable()();

  // Auth & shift tracking (added in v5)
  TextColumn get cashierUserId => text().nullable()();
  TextColumn get shiftId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionItems extends Table {
  TextColumn get id => text()();

  TextColumn get transactionId => text()();
  TextColumn get productId => text()();
  // Snapshot nama produk saat transaksi - dengan default untuk migration
  TextColumn get productName => text().withDefault(const Constant(''))();

  IntColumn get qty => integer()();
  IntColumn get priceAtSale => integer()(); // snapshot harga saat jual
  IntColumn get subtotal => integer()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE',
        // Tidak ada foreign key ke products karena produk bisa dihapus
        // tapi riwayat tetap harus bisa menampilkan nama produk
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
  TextColumn get pinHash => text()(); // SHA-256(PIN + salt)
  TextColumn get salt => text()(); // Random salt for hashing
  TextColumn get role => text()(); // 'owner' or 'cashier'
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Recovery code fields (for owner PIN recovery)
  TextColumn get recoveryHash => text().nullable()();
  TextColumn get recoverySalt => text().nullable()();
  DateTimeColumn get recoveryCreatedAt => dateTime().nullable()();
  DateTimeColumn get recoveryUsedAt => dateTime().nullable()();
  IntColumn get recoveryAttempts =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get recoveryLockedUntil => dateTime().nullable()();

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
  TextColumn get code => text()(); // e.g., 'manage_products'
  TextColumn get name => text()(); // e.g., 'Manage Products'
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Constructor untuk testing dengan custom executor
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // Migration dari versi 1 ke 2
      if (from < 2) {
        await m.createTable(transactions);
        await m.createTable(transactionItems);
      }
      // Migration dari versi 2 ke 3: tambah kolom productName
      if (from < 3) {
        await m.addColumn(transactionItems, transactionItems.productName);
        // Update data lama: isi productName dari products table jika ada
        await customStatement('''
          UPDATE transaction_items
          SET product_name = COALESCE(
            (SELECT name FROM products WHERE products.id = transaction_items.product_id),
            'Produk tidak diketahui'
          )
        ''');
      }
      // Migration dari versi 3 ke 4: tambah table categories dan kolom categoryId di products
      if (from < 4) {
        await m.createTable(categories);
        await m.addColumn(products, products.categoryId);
      }
      // Migration dari versi 4 ke 5: authentication & shift system
      if (from < 5) {
        // 1. Create auth tables
        await m.createTable(users);
        await m.createTable(shifts);
        await m.createTable(permissions);
        await m.createTable(userPermissions);

        // 2. Add columns to transactions for shift tracking
        await m.addColumn(transactions, transactions.cashierUserId);
        await m.addColumn(transactions, transactions.shiftId);

        // 3. Seed permissions
        await _seedPermissions();
      }
      // Migration dari versi 5 ke 6: add recovery columns for owner PIN recovery
      if (from < 6) {
        await m.addColumn(users, users.recoveryHash);
        await m.addColumn(users, users.recoverySalt);
        await m.addColumn(users, users.recoveryCreatedAt);
        await m.addColumn(users, users.recoveryUsedAt);
        await m.addColumn(users, users.recoveryAttempts);
        await m.addColumn(users, users.recoveryLockedUntil);
      }
    },
    beforeOpen: (details) async {
      if (details.hadUpgrade || details.wasCreated) {
        // Ensure permissions are seeded after create or upgrade
        if (details.wasCreated || details.versionBefore! < 5) {
          await _seedPermissions();
        }
      }
    },
  );

  /// Seed permissions data
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

  /// Reset database - hapus semua data dan mulai fresh
  Future<void> resetDatabase() async {
    await transaction(() async {
      await delete(transactionItems).go();
      await delete(transactions).go();
      await delete(products).go();
      await delete(categories).go();
    });
  }

  /// ---- CATEGORIES ----
  
  Stream<List<Category>> watchCategories() {
    return (select(categories)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  Future<void> upsertCategory({
    required String id,
    required String name,
  }) async {
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion(
        id: Value(id),
        name: Value(name),
      ),
    );
  }

  Future<void> deleteCategory(String id) async {
    // Set produk yang punya kategori ini jadi null dulu (optional, but safer)
    await (update(products)..where((p) => p.categoryId.equals(id)))
        .write(const ProductsCompanion(categoryId: Value(null)));
        
    await (delete(categories)..where((t) => t.id.equals(id))).go();
  }

  /// ---- PRODUCTS ----

  // Update query to join with categories if needed, but for now just simple select is fine
  // or simple stream
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
  }) async {
    final data = ProductsCompanion(
      id: Value(id),
      name: Value(name),
      price: Value(price),
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      trackStock: Value(trackStock),
      stock: Value(trackStock ? stock : null),
    );

    await into(products).insertOnConflictUpdate(data);
  }

  Future<void> deleteProduct(String id) async {
    await (delete(products)..where((t) => t.id.equals(id))).go();
  }

  /// ---- SALES ----
  ///
  /// Unified method untuk membuat transaksi (cash atau qris)
  /// [paymentMethod] - 'cash' atau 'qris'
  /// [cashReceived] - wajib jika cash, null jika qris
  /// [cashierUserId] - optional: ID of cashier who performed the transaction
  /// [shiftId] - optional: ID of shift when transaction was made
  Future<void> createSale({
    required String transactionId,
    required List<SaleLine> lines,
    required String paymentMethod,
    int? cashReceived,
    String? cashierUserId,
    String? shiftId,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Cart kosong');
    }

    final total = lines.fold<int>(0, (s, l) => s + l.subtotal);

    // Validasi untuk cash payment
    if (paymentMethod == 'cash') {
      if (cashReceived == null) {
        throw ArgumentError('Cash received wajib diisi untuk pembayaran cash');
      }
      if (cashReceived < total) {
        throw ArgumentError('Uang diterima kurang');
      }
    }

    final changeAmount = paymentMethod == 'cash' ? (cashReceived! - total) : null;

    await transaction(() async {
      // 1) Validasi stok
      await _validateStock(lines);

      // 2) Insert transaksi
      await into(transactions).insert(
        TransactionsCompanion(
          id: Value(transactionId),
          total: Value(total),
          paymentMethod: Value(paymentMethod),
          cashReceived: Value(cashReceived),
          change: Value(changeAmount),
          cashierUserId: Value(cashierUserId),
          shiftId: Value(shiftId),
        ),
      );

      // 3) Insert items dengan unique ID dan snapshot nama produk
      await _insertTransactionItems(transactionId, lines);

      // 4) Update stok
      await _updateStock(lines);
    });
  }

  /// Validasi ketersediaan stok untuk semua item
  Future<void> _validateStock(List<SaleLine> lines) async {
    for (final line in lines) {
      if (!line.trackStock) continue;

      final product = await (select(products)
            ..where((t) => t.id.equals(line.productId)))
          .getSingle();
      final currentStock = product.stock ?? 0;

      if (currentStock < line.qty) {
        throw StateError('Stok tidak cukup untuk "${product.name}"');
      }
    }
  }

  /// Insert item transaksi dengan unique ID dan snapshot nama produk
  Future<void> _insertTransactionItems(
    String transactionId,
    List<SaleLine> lines,
  ) async {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final itemId = _generateUniqueId();

      await into(transactionItems).insert(
        TransactionItemsCompanion(
          id: Value(itemId),
          transactionId: Value(transactionId),
          productId: Value(line.productId),
          productName: Value(line.productName), // Snapshot nama produk
          qty: Value(line.qty),
          priceAtSale: Value(line.priceAtSale),
          subtotal: Value(line.subtotal),
        ),
      );
    }
  }

  /// Update stok setelah penjualan
  Future<void> _updateStock(List<SaleLine> lines) async {
    for (final line in lines) {
      if (!line.trackStock) continue;

      final product = await (select(products)
            ..where((t) => t.id.equals(line.productId)))
          .getSingle();
      final currentStock = product.stock ?? 0;
      final newStock = currentStock - line.qty;

      await (update(products)..where((t) => t.id.equals(line.productId)))
          .write(ProductsCompanion(stock: Value(newStock)));
    }
  }

  /// ---- TRANSACTIONS / HISTORY ----

  Stream<List<Transaction>> watchTransactions() {
    return (select(transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Get transaction items - langsung pakai snapshot nama dari database
  Future<List<TransactionItem>> getTransactionItems(String transactionId) async {
    return (select(transactionItems)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
  }

  /// ---- REPORTS ----

  /// Get transactions for a specific date range
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

  /// Get report summary for a specific date
  Future<ReportSummary> getReportSummary(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final dayTransactions = await getTransactionsByDateRange(startOfDay, endOfDay);

    final totalOrders = dayTransactions.length;
    final totalIncome = dayTransactions.fold<int>(0, (sum, tx) => sum + tx.total);

    // Breakdown by payment method
    final cashTransactions = dayTransactions.where((tx) => tx.paymentMethod == 'cash').toList();
    final qrisTransactions = dayTransactions.where((tx) => tx.paymentMethod == 'qris').toList();

    final cashTotal = cashTransactions.fold<int>(0, (sum, tx) => sum + tx.total);
    final qrisTotal = qrisTransactions.fold<int>(0, (sum, tx) => sum + tx.total);

    // Get top selling products
    final topProducts = await getTopSellingProducts(startOfDay, endOfDay);

    return ReportSummary(
      date: date,
      totalOrders: totalOrders,
      totalIncome: totalIncome,
      cashOrders: cashTransactions.length,
      cashTotal: cashTotal,
      qrisOrders: qrisTransactions.length,
      qrisTotal: qrisTotal,
      transactions: dayTransactions,
      topProducts: topProducts,
    );
  }

  /// Get top selling products within a date range
  Future<List<TopProduct>> getTopSellingProducts(
    DateTime startDate,
    DateTime endDate, {
    int limit = 5,
  }) async {
    // Unix timestamp for SQLite comparison if needed, but Drift handles DateTime well usually.
    // Making sure we are using the same timezone logic as other queries.
    // However, raw SQL in Drift uses epoch seconds for DateTime.
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

  /// Get employee report summary for a specific date
  Future<List<EmployeeReportSummary>> getEmployeeReportSummary(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    // Get all transactions for the day
    final dayTransactions = await getTransactionsByDateRange(startOfDay, endOfDay);
    
    // Get unique user IDs
    final userIds = dayTransactions
        .where((tx) => tx.cashierUserId != null)
        .map((tx) => tx.cashierUserId!)
        .toSet();
    
    final List<EmployeeReportSummary> employeeReports = [];
    
    for (final userId in userIds) {
      // Get user info
      final user = await (select(users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (user == null) continue;
      
      // Get user's transactions for the day
      final userTransactions = dayTransactions
          .where((tx) => tx.cashierUserId == userId)
          .toList();
      
      // Calculate totals
      final totalIncome = userTransactions.fold<int>(0, (sum, tx) => sum + tx.total);
      final cashTx = userTransactions.where((tx) => tx.paymentMethod == 'cash').toList();
      final qrisTx = userTransactions.where((tx) => tx.paymentMethod == 'qris').toList();
      final cashTotal = cashTx.fold<int>(0, (sum, tx) => sum + tx.total);
      final qrisTotal = qrisTx.fold<int>(0, (sum, tx) => sum + tx.total);
      
      // Get shift IDs for this user on this day
      final shiftIds = userTransactions
          .where((tx) => tx.shiftId != null)
          .map((tx) => tx.shiftId!)
          .toSet();
      
      // Get shift info
      final List<ShiftInfo> shiftInfos = [];
      for (final shiftId in shiftIds) {
        final shift = await (select(shifts)..where((s) => s.id.equals(shiftId))).getSingleOrNull();
        if (shift != null) {
          final shiftTx = userTransactions.where((tx) => tx.shiftId == shiftId).toList();
          shiftInfos.add(ShiftInfo(
            shiftId: shiftId,
            startAt: shift.startAt,
            endAt: shift.endAt,
            transactionCount: shiftTx.length,
            totalIncome: shiftTx.fold<int>(0, (sum, tx) => sum + tx.total),
          ));
        }
      }
      
      // Sort shifts by start time
      shiftInfos.sort((a, b) => a.startAt.compareTo(b.startAt));
      
      // Calculate top products for this employee
      final topProducts = await _getTopProductsForTransactions(userTransactions);
      
      employeeReports.add(EmployeeReportSummary(
        userId: userId,
        username: user.username,
        totalTransactions: userTransactions.length,
        totalIncome: totalIncome,
        cashOrders: cashTx.length,
        cashTotal: cashTotal,
        qrisOrders: qrisTx.length,
        qrisTotal: qrisTotal,
        shifts: shiftInfos,
        transactions: userTransactions,
        topProducts: topProducts,
      ));
    }
    
    // Sort by total income descending
    employeeReports.sort((a, b) => b.totalIncome.compareTo(a.totalIncome));
    
    return employeeReports;
  }
  
  /// Get top products for a list of transactions
  Future<List<TopProduct>> _getTopProductsForTransactions(List<Transaction> txList, {int limit = 5}) async {
    if (txList.isEmpty) return [];
    
    // Get all transaction items for these transactions
    final Map<String, TopProduct> productMap = {};
    
    for (final tx in txList) {
      final items = await getTransactionItems(tx.id);
      for (final item in items) {
        final existingProduct = productMap[item.productName];
        if (existingProduct != null) {
          productMap[item.productName] = TopProduct(
            productName: item.productName,
            totalQty: existingProduct.totalQty + item.qty,
            totalSales: existingProduct.totalSales + item.subtotal,
          );
        } else {
          productMap[item.productName] = TopProduct(
            productName: item.productName,
            totalQty: item.qty,
            totalSales: item.subtotal,
          );
        }
      }
    }
    
    final sortedProducts = productMap.values.toList()
      ..sort((a, b) => b.totalQty.compareTo(a.totalQty));
    
    return sortedProducts.take(limit).toList();
  }

  /// Get report summary for a month
  Future<ReportSummary> getMonthlyReportSummary(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);

    final monthTransactions = await getTransactionsByDateRange(startOfMonth, endOfMonth);

    final totalOrders = monthTransactions.length;
    final totalIncome = monthTransactions.fold<int>(0, (sum, tx) => sum + tx.total);

    final cashTransactions = monthTransactions.where((tx) => tx.paymentMethod == 'cash').toList();
    final qrisTransactions = monthTransactions.where((tx) => tx.paymentMethod == 'qris').toList();

    final cashTotal = cashTransactions.fold<int>(0, (sum, tx) => sum + tx.total);
    final qrisTotal = qrisTransactions.fold<int>(0, (sum, tx) => sum + tx.total);

    final topProducts = await getTopSellingProducts(startOfMonth, endOfMonth);

    return ReportSummary(
      date: startOfMonth,
      totalOrders: totalOrders,
      totalIncome: totalIncome,
      cashOrders: cashTransactions.length,
      cashTotal: cashTotal,
      qrisOrders: qrisTransactions.length,
      qrisTotal: qrisTotal,
      transactions: monthTransactions,
      topProducts: topProducts,
    );
  }

  /// Get daily trends for a month (income & orders per day)
  Future<List<DailyTrend>> getDailyTrends(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);
    final daysInMonth = endOfMonth.difference(startOfMonth).inDays;

    final monthTransactions = await getTransactionsByDateRange(startOfMonth, endOfMonth);

    final List<DailyTrend> trends = [];
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final dayTx = monthTransactions.where((tx) {
        return tx.createdAt.year == year && tx.createdAt.month == month && tx.createdAt.day == day;
      }).toList();

      trends.add(DailyTrend(
        date: date,
        orders: dayTx.length,
        income: dayTx.fold<int>(0, (sum, tx) => sum + tx.total),
      ));
    }

    return trends;
  }

  /// Get employee report summary for a date range
  Future<List<EmployeeReportSummary>> getEmployeeReportSummaryForRange(DateTime startDate, DateTime endDate) async {
    final rangeTx = await getTransactionsByDateRange(startDate, endDate);
    
    final userIds = rangeTx
        .where((tx) => tx.cashierUserId != null)
        .map((tx) => tx.cashierUserId!)
        .toSet();
    
    final List<EmployeeReportSummary> employeeReports = [];
    
    for (final userId in userIds) {
      final user = await (select(users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (user == null) continue;
      
      final userTransactions = rangeTx
          .where((tx) => tx.cashierUserId == userId)
          .toList();
      
      final totalIncome = userTransactions.fold<int>(0, (sum, tx) => sum + tx.total);
      final cashTx = userTransactions.where((tx) => tx.paymentMethod == 'cash').toList();
      final qrisTx = userTransactions.where((tx) => tx.paymentMethod == 'qris').toList();
      
      // Get shifts for this user in the range
      final userShifts = await (select(shifts)
        ..where((s) => s.userId.equals(userId) &
            s.startAt.isBiggerOrEqualValue(startDate) &
            s.startAt.isSmallerThanValue(endDate))
        ..orderBy([(s) => OrderingTerm.desc(s.startAt)]))
        .get();
      
      final shiftInfoList = <ShiftInfo>[];
      for (final shift in userShifts) {
        final shiftTx = userTransactions.where((tx) => tx.shiftId == shift.id).toList();
        shiftInfoList.add(ShiftInfo(
          shiftId: shift.id,
          startAt: shift.startAt,
          endAt: shift.endAt,
          transactionCount: shiftTx.length,
          totalIncome: shiftTx.fold<int>(0, (sum, tx) => sum + tx.total),
        ));
      }
      
      final topProducts = await _getTopProductsForTransactions(userTransactions);
      
      employeeReports.add(EmployeeReportSummary(
        userId: userId,
        username: user.username,
        totalTransactions: userTransactions.length,
        totalIncome: totalIncome,
        cashOrders: cashTx.length,
        cashTotal: cashTx.fold<int>(0, (sum, tx) => sum + tx.total),
        qrisOrders: qrisTx.length,
        qrisTotal: qrisTx.fold<int>(0, (sum, tx) => sum + tx.total),
        shifts: shiftInfoList,
        transactions: userTransactions,
        topProducts: topProducts,
      ));
    }
    
    employeeReports.sort((a, b) => b.totalIncome.compareTo(a.totalIncome));
    return employeeReports;
  }
}

/// Model untuk summary laporan
class ReportSummary {
  final DateTime date;
  final int totalOrders;
  final int totalIncome;
  final int cashOrders;
  final int cashTotal;
  final int qrisOrders;
  final int qrisTotal;
  final List<Transaction> transactions;
  final List<TopProduct> topProducts;

  ReportSummary({
    required this.date,
    required this.totalOrders,
    required this.totalIncome,
    required this.cashOrders,
    required this.cashTotal,
    required this.qrisOrders,
    required this.qrisTotal,
    required this.transactions,
    required this.topProducts,
  });
}

/// Model untuk summary laporan per karyawan
class EmployeeReportSummary {
  final String userId;
  final String username;
  final int totalTransactions;
  final int totalIncome;
  final int cashOrders;
  final int cashTotal;
  final int qrisOrders;
  final int qrisTotal;
  final List<ShiftInfo> shifts;
  final List<Transaction> transactions;
  final List<TopProduct> topProducts;

  EmployeeReportSummary({
    required this.userId,
    required this.username,
    required this.totalTransactions,
    required this.totalIncome,
    required this.cashOrders,
    required this.cashTotal,
    required this.qrisOrders,
    required this.qrisTotal,
    required this.shifts,
    required this.transactions,
    required this.topProducts,
  });
}

/// Model untuk informasi shift
class ShiftInfo {
  final String shiftId;
  final DateTime startAt;
  final DateTime? endAt;
  final int transactionCount;
  final int totalIncome;

  ShiftInfo({
    required this.shiftId,
    required this.startAt,
    this.endAt,
    required this.transactionCount,
    required this.totalIncome,
  });
}

/// Model untuk tren harian (grafik bulanan)
class DailyTrend {
  final DateTime date;
  final int orders;
  final int income;

  DailyTrend({
    required this.date,
    required this.orders,
    required this.income,
  });
}

/// =======================
/// UTILITY
/// =======================

/// Generate unique ID dengan timestamp + random
String _generateUniqueId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(99999).toString().padLeft(5, '0');
  return '${timestamp}_$random';
}

/// =======================
/// DB CONNECTION
/// =======================
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kasir_app.sqlite'));
    return NativeDatabase(file);
  });
}

/// Hapus file database untuk reset total
Future<void> deleteDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'kasir_app.sqlite'));
  if (await file.exists()) {
    await file.delete();
  }
}
