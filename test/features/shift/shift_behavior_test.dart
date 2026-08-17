import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('login shift lifecycle', () {
    test('owner login TIDAK membuka shift (shiftId null)', () async {
      SharedPreferences.setMockInitialValues({});
      final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dbTest.close);
      final repo = AuthRepository(dbTest);

      await repo.bootstrapOwner(username: 'owner', pin: '1234');

      final session = await repo.login(username: 'owner', pin: '1234');

      expect(session, isNotNull);
      expect(session!.shiftId, isNull, reason: 'owner tidak menjalankan shift');

      final shifts = await dbTest.select(dbTest.shifts).get();
      expect(shifts, isEmpty, reason: 'tidak ada shift dibuat untuk owner');
    });

    test('cashier login membuka shift baru di business-nya', () async {
      SharedPreferences.setMockInitialValues({});
      final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dbTest.close);
      final repo = AuthRepository(dbTest);

      await dbTest.into(dbTest.businesses).insert(BusinessesCompanion.insert(
            id: const Value('biz-a'),
            name: 'Teras Inn',
            type: 'restaurant_dinein',
          ));

      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPin('4321', salt);
      await dbTest.into(dbTest.users).insert(UsersCompanion.insert(
            id: const Value('cashier-1'),
            username: 'sari',
            pinHash: hash,
            salt: salt,
            role: 'cashier',
          ));
      await dbTest
          .into(dbTest.userBusinessRoles)
          .insert(UserBusinessRolesCompanion.insert(
            userId: 'cashier-1',
            businessId: 'biz-a',
            role: 'cashier',
          ));

      final session = await repo.login(username: 'sari', pin: '4321');

      expect(session, isNotNull);
      expect(session!.shiftId, isNotNull, reason: 'cashier harus punya shift');

      final shifts = await dbTest.select(dbTest.shifts).get();
      expect(shifts, hasLength(1));
      expect(shifts.first.businessId, 'biz-a');
      expect(shifts.first.userId, 'cashier-1');
      expect(shifts.first.endAt, isNull, reason: 'shift baru masih aktif');
    });
  });

}
