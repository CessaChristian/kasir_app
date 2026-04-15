import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'app_database.dart';
import 'db.dart';

/// Inject demo data for testing reports & excel export.
/// Call once, then remove the call.
Future<void> seedDemoData() async {
  // Check if demo data already exists
  final existing = await (db.select(db.transactions)
        ..where((t) => t.id.like('demo_%')))
      .get();
  if (existing.isNotEmpty) {
    debugPrint('⚠️ Demo data already exists (${existing.length} transactions). Skipping.');
    return;
  }

  debugPrint('🌱 Seeding demo data...');
  final rng = Random(42);

  // ---- Categories ----
  const categories = [
    {'id': 'demo_cat_1', 'name': 'Makanan'},
    {'id': 'demo_cat_2', 'name': 'Minuman'},
    {'id': 'demo_cat_3', 'name': 'Snack'},
  ];

  for (final c in categories) {
    await db.into(db.categories).insertOnConflictUpdate(
      CategoriesCompanion.insert(id: c['id']!, name: c['name']!),
    );
  }

  // ---- Products ----
  final products = [
    {'id': 'demo_prod_1', 'name': 'Nasi Goreng', 'price': 25000, 'cat': 'demo_cat_1'},
    {'id': 'demo_prod_2', 'name': 'Mie Ayam', 'price': 20000, 'cat': 'demo_cat_1'},
    {'id': 'demo_prod_3', 'name': 'Ayam Bakar', 'price': 30000, 'cat': 'demo_cat_1'},
    {'id': 'demo_prod_4', 'name': 'Nasi Campur', 'price': 28000, 'cat': 'demo_cat_1'},
    {'id': 'demo_prod_5', 'name': 'Soto Ayam', 'price': 22000, 'cat': 'demo_cat_1'},
    {'id': 'demo_prod_6', 'name': 'Es Teh Manis', 'price': 5000, 'cat': 'demo_cat_2'},
    {'id': 'demo_prod_7', 'name': 'Es Jeruk', 'price': 8000, 'cat': 'demo_cat_2'},
    {'id': 'demo_prod_8', 'name': 'Kopi Hitam', 'price': 7000, 'cat': 'demo_cat_2'},
    {'id': 'demo_prod_9', 'name': 'Teh Hangat', 'price': 4000, 'cat': 'demo_cat_2'},
    {'id': 'demo_prod_10', 'name': 'Kerupuk', 'price': 3000, 'cat': 'demo_cat_3'},
    {'id': 'demo_prod_11', 'name': 'Gorengan', 'price': 5000, 'cat': 'demo_cat_3'},
  ];

  for (final p in products) {
    await db.into(db.products).insertOnConflictUpdate(
      ProductsCompanion.insert(
        id: p['id'] as String,
        name: p['name'] as String,
        price: p['price'] as int,
        categoryId: Value(p['cat'] as String),
      ),
    );
  }

  // ---- Users (demo cashiers) ----
  // We'll use existing users if any, otherwise create demo ones
  var allUsers = await db.select(db.users).get();
  if (allUsers.isEmpty) {
    // Create demo users only if none exist
    await db.into(db.users).insertOnConflictUpdate(
      UsersCompanion.insert(
        id: 'demo_user_1',
        username: 'Kasir Demo 1',
        pinHash: 'demo',
        salt: 'demo',
        role: 'cashier',
      ),
    );
    await db.into(db.users).insertOnConflictUpdate(
      UsersCompanion.insert(
        id: 'demo_user_2',
        username: 'Kasir Demo 2',
        pinHash: 'demo',
        salt: 'demo',
        role: 'cashier',
      ),
    );
    allUsers = await db.select(db.users).get();
  }

  final userIds = allUsers.map((u) => u.id).toList();
  final paymentMethods = ['cash', 'qris'];

  // ---- Generate Transactions for 7 days ----
  final now = DateTime.now();
  int txCount = 0;

  for (int d = 0; d < 7; d++) {
    final date = now.subtract(Duration(days: d));
    final numTransactions = 8 + rng.nextInt(10); // 8-17 transactions per day

    // Create a shift for this day
    final userId = userIds[d % userIds.length];
    final shiftId = 'demo_shift_$d';
    final shiftStart = DateTime(date.year, date.month, date.day, 7, 0);
    final shiftEnd = DateTime(date.year, date.month, date.day, 21, 0);

    await db.into(db.shifts).insertOnConflictUpdate(
      ShiftsCompanion.insert(
        id: shiftId,
        userId: userId,
        startAt: Value(shiftStart),
        endAt: Value(shiftEnd),
      ),
    );

    for (int t = 0; t < numTransactions; t++) {
      final txId = 'demo_tx_${d}_$t';
      final hour = 8 + rng.nextInt(12); // 08:00 - 19:59
      final minute = rng.nextInt(60);
      final txTime = DateTime(date.year, date.month, date.day, hour, minute);

      // Pick 1-4 items for this transaction
      final numItems = 1 + rng.nextInt(4);
      final selectedProducts = List.from(products)..shuffle(rng);
      final chosenProducts = selectedProducts.take(numItems).toList();

      int txTotal = 0;
      final itemInserts = <Future>[];

      for (int i = 0; i < chosenProducts.length; i++) {
        final prod = chosenProducts[i];
        final qty = 1 + rng.nextInt(3);
        final price = prod['price'] as int;
        final subtotal = price * qty;
        txTotal += subtotal;

        itemInserts.add(
          db.into(db.transactionItems).insertOnConflictUpdate(
            TransactionItemsCompanion.insert(
              id: 'demo_item_${d}_${t}_$i',
              transactionId: txId,
              productId: prod['id'] as String,
              productName: Value(prod['name'] as String),
              qty: qty,
              priceAtSale: price,
              subtotal: subtotal,
            ),
          ),
        );
      }

      final method = paymentMethods[rng.nextInt(2)];
      final cashReceived = method == 'cash' ? ((txTotal ~/ 10000) + 1) * 10000 : null;
      final change = cashReceived != null ? cashReceived - txTotal : null;

      await db.into(db.transactions).insertOnConflictUpdate(
        TransactionsCompanion.insert(
          id: txId,
          total: txTotal,
          paymentMethod: method,
          createdAt: Value(txTime),
          cashReceived: Value(cashReceived),
          change: Value(change),
          cashierUserId: Value(userId),
          shiftId: Value(shiftId),
        ),
      );

      await Future.wait(itemInserts);
      txCount++;
    }
  }

  debugPrint('✅ Seeded $txCount demo transactions across 7 days');
}
