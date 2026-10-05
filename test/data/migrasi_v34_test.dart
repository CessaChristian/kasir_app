import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/sales/cart_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// v34: Take Away digabung ke Dine In (permintaan owner 2026-10-05).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('migrasi v33 → v34: take_away jadi dine_in dan dikirim ulang', () async {
    final folder = Directory.systemTemp.createTempSync('uji_v34');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v33.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    Future<void> catat(String id, String tipe) => lama
        .into(lama.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: Value(id),
            total: 10000,
            paymentMethod: 'cash',
            orderType: Value(tipe),
            updatedAt: Value(DateTime(2026, 1, 1)),
            syncStatus: const Value('synced'),
          ),
        );
    await catat('t-bawa', 'take_away');
    await catat('t-makan', 'dine_in');
    await catat('t-antar', 'delivery');
    await lama.close();

    final mentah = sqlite3.open(jalur);
    mentah.execute('PRAGMA user_version = 33');
    mentah.dispose();

    final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baru.close);
    final semua = {
      for (final t in await baru.select(baru.transactions).get()) t.id: t,
    };

    expect(semua['t-bawa']!.orderType, 'dine_in');
    expect(
      semua['t-bawa']!.syncStatus,
      'pending',
      reason: 'perubahan harus sampai ke server',
    );
    expect(
      semua['t-bawa']!.updatedAt.isAfter(DateTime(2026, 1, 1)),
      isTrue,
      reason: 'lebih baru dari salinan server lama',
    );

    // Yang bukan Take Away tidak disentuh.
    for (final id in ['t-makan', 't-antar']) {
      expect(semua[id]!.syncStatus, 'synced', reason: id);
    }
    expect(semua['t-antar']!.orderType, 'delivery');
  });

  test('keranjang hanya menawarkan Dine In dan Delivery', () {
    expect(OrderType.values.map((t) => t.value), ['dine_in', 'delivery']);
  });
}
