import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/business_context.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/business/services/business_switch_service.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('activate: tutup shift lama, buka shift baru di business target',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    BusinessContext.dbOverride = dbTest;
    SessionManager.dbOverride = dbTest;
    BusinessSwitchService.dbOverride = dbTest;
    addTearDown(() async {
      BusinessContext.dbOverride = null;
      SessionManager.dbOverride = null;
      BusinessSwitchService.dbOverride = null;
      BusinessContext.instance.clear();
      await SessionManager.instance.clearSession();
    });

    const userId = 'user-1';
    for (final b in [
      (id: 'biz-a', name: 'Teras Inn', type: 'restaurant_dinein'),
      (id: 'biz-b', name: 'Thai Tea', type: 'beverage_grabandgo'),
    ]) {
      await dbTest.into(dbTest.businesses).insert(BusinessesCompanion.insert(
            id: Value(b.id),
            name: b.name,
            type: b.type,
          ));
      await dbTest
          .into(dbTest.userBusinessRoles)
          .insert(UserBusinessRolesCompanion.insert(
            userId: userId,
            businessId: b.id,
            role: 'owner',
          ));
    }
    // Shift aktif di business A
    await dbTest.into(dbTest.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-lama'),
          businessId: 'biz-a',
          userId: userId,
        ));

    await SessionManager.instance.setSession(AuthSession.create(
      userId: userId,
      username: 'owner',
      role: 'owner',
      shiftId: 'shift-lama',
      permissions: const [],
    ));
    await BusinessContext.instance.loadInitial(userId: userId);

    await BusinessSwitchService.activate('biz-b');

    final shiftLama = await (dbTest.select(dbTest.shifts)
          ..where((s) => s.id.equals('shift-lama')))
        .getSingle();
    expect(shiftLama.endAt, isNotNull, reason: 'shift lama harus ditutup');

    final shiftBaru = await (dbTest.select(dbTest.shifts)
          ..where((s) => s.businessId.equals('biz-b')))
        .getSingle();
    expect(shiftBaru.endAt, isNull, reason: 'shift baru harus aktif');

    expect(SessionManager.instance.currentShiftId, shiftBaru.id);
    expect(BusinessContext.instance.activeBusinessId, 'biz-b');
  });

  test('activate ke business tanpa akses: gagal SEBELUM menyentuh shift',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    BusinessContext.dbOverride = dbTest;
    SessionManager.dbOverride = dbTest;
    BusinessSwitchService.dbOverride = dbTest;
    addTearDown(() async {
      BusinessContext.dbOverride = null;
      SessionManager.dbOverride = null;
      BusinessSwitchService.dbOverride = null;
      BusinessContext.instance.clear();
      await SessionManager.instance.clearSession();
    });

    const userId = 'user-1';
    await dbTest.into(dbTest.businesses).insert(BusinessesCompanion.insert(
          id: const Value('biz-a'),
          name: 'Teras Inn',
          type: 'restaurant_dinein',
        ));
    await dbTest
        .into(dbTest.userBusinessRoles)
        .insert(UserBusinessRolesCompanion.insert(
          userId: userId,
          businessId: 'biz-a',
          role: 'owner',
        ));
    await dbTest.into(dbTest.shifts).insert(ShiftsCompanion.insert(
          id: const Value('shift-lama'),
          businessId: 'biz-a',
          userId: userId,
        ));
    await SessionManager.instance.setSession(AuthSession.create(
      userId: userId,
      username: 'owner',
      role: 'owner',
      shiftId: 'shift-lama',
      permissions: const [],
    ));

    await expectLater(
      BusinessSwitchService.activate('biz-tanpa-akses'),
      throwsA(isA<UnauthorizedException>()),
    );

    final shiftLama = await (dbTest.select(dbTest.shifts)
          ..where((s) => s.id.equals('shift-lama')))
        .getSingle();
    expect(shiftLama.endAt, isNull,
        reason: 'shift TIDAK boleh tertutup kalau akses ditolak');
  });
}
