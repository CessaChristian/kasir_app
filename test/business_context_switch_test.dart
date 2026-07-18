import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/business_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> _makeBusiness(
  AppDatabase db,
  String id,
  String name,
  String type,
  String userId,
) async {
  await db.into(db.businesses).insert(BusinessesCompanion.insert(
        id: Value(id),
        name: name,
        type: type,
      ));
  await db.into(db.userBusinessRoles).insert(UserBusinessRolesCompanion.insert(
        userId: userId,
        businessId: id,
        role: 'owner',
      ));
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switchTo me-reload availableBusinesses (fix switcher basi)', () async {
    SharedPreferences.setMockInitialValues({});
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    BusinessContext.dbOverride = dbTest;
    addTearDown(() {
      BusinessContext.dbOverride = null;
      BusinessContext.instance.clear();
    });

    const userId = 'user-1';
    await _makeBusiness(dbTest, 'biz-a', 'Teras Inn', 'restaurant_dinein', userId);
    await BusinessContext.instance.loadInitial(userId: userId);
    expect(BusinessContext.instance.availableBusinesses.length, 1);

    // Business kedua dibuat SETELAH loadInitial — daftar lama pasti belum memuatnya.
    await _makeBusiness(dbTest, 'biz-b', 'Thai Tea', 'beverage_grabgo', userId);
    await BusinessContext.instance.switchTo('biz-b', userId: userId);

    expect(BusinessContext.instance.activeBusinessId, 'biz-b');
    expect(BusinessContext.instance.availableBusinesses.length, 2,
        reason: 'switchTo harus me-reload daftar business');
  });

  test('loadPersistedForBranding set business tanpa session', () async {
    SharedPreferences.setMockInitialValues({'active_business_id': 'biz-b'});
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    BusinessContext.dbOverride = dbTest;
    addTearDown(() {
      BusinessContext.dbOverride = null;
      BusinessContext.instance.clear();
    });
    BusinessContext.instance.clear();

    await _makeBusiness(dbTest, 'biz-a', 'Teras Inn', 'restaurant_dinein', 'u');
    await _makeBusiness(dbTest, 'biz-b', 'Thai Tea', 'beverage_grabgo', 'u');

    await BusinessContext.instance.loadPersistedForBranding();
    expect(BusinessContext.instance.activeBusinessId, 'biz-b');
  });
}
