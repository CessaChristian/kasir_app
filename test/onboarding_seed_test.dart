import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/onboarding/repositories/onboarding_repository.dart';

void main() {
  test('setupFirstOwner seed satu business + role owner', () async {
    final dbTest = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbTest.close);
    OnboardingRepository.dbOverride = dbTest;
    addTearDown(() => OnboardingRepository.dbOverride = null);

    final result = await OnboardingRepository().setupFirstOwner(
      username: 'owner',
      pinHash: 'hash',
      salt: 'salt',
    );

    // Aplikasi difokuskan ke Teras Inn; Thai Tea belum buka. Struktur
    // multi-business tetap ada, tinggal menambah entri di kSeedBusinesses.
    final businesses = await dbTest.select(dbTest.businesses).get();
    expect(businesses.length, kSeedBusinesses.length);
    expect(businesses.single.name, 'Teras Inn');
    expect(businesses.single.type, 'restaurant_dinein');

    final roles = await dbTest.select(dbTest.userBusinessRoles).get();
    expect(roles.length, kSeedBusinesses.length);
    expect(roles.every((r) => r.role == 'owner' && r.userId == result.userId),
        isTrue);

    // terasInnId harus menunjuk business dine-in (business utama).
    final teras = businesses.firstWhere((b) => b.type == 'restaurant_dinein');
    expect(result.terasInnId, teras.id);
  });
}
