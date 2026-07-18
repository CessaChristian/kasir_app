import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/onboarding/repositories/onboarding_repository.dart';

void main() {
  test('setupFirstOwner seed 2 business hardcode + role owner keduanya',
      () async {
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    OnboardingRepository.dbOverride = dbTest;
    addTearDown(() => OnboardingRepository.dbOverride = null);

    final result = await OnboardingRepository().setupFirstOwner(
      username: 'owner',
      pinHash: 'hash',
      salt: 'salt',
    );

    final businesses = await dbTest.select(dbTest.businesses).get();
    expect(businesses.length, 2);
    expect(businesses.map((b) => b.type).toSet(),
        {'restaurant_dinein', 'beverage_grabandgo'});
    expect(businesses.map((b) => b.name).toSet(), {'Teras Inn', 'Thai Tea'});

    final roles = await dbTest.select(dbTest.userBusinessRoles).get();
    expect(roles.length, 2);
    expect(roles.every((r) => r.role == 'owner' && r.userId == result.userId),
        isTrue);

    // terasInnId harus menunjuk business dine-in (business utama saat ini).
    final teras = businesses.firstWhere((b) => b.type == 'restaurant_dinein');
    expect(result.terasInnId, teras.id);
  });
}
