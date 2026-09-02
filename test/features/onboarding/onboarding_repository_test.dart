import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/onboarding/repositories/onboarding_repository.dart';

/// Onboarding sejak v13 hanya membuat akun owner.
///
/// Sebelumnya ia juga menyemai tabel `businesses` beserta baris
/// `user_business_roles`. Keduanya dibuang karena aplikasi difokuskan ke satu
/// bisnis, dan peran user cukup dibaca dari `users.role`.
///
/// Test lama menguji "pola yang setara" dengan menyalin isi repository ke
/// dalam test — sehingga perubahan pada repository tidak akan ketahuan. Di
/// sini repository aslinya yang dipanggil, lewat `dbOverride`.
void main() {
  late AppDatabase db;
  late OnboardingRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    OnboardingRepository.dbOverride = db;
    repo = OnboardingRepository();
  });

  tearDown(() async {
    OnboardingRepository.dbOverride = null;
    await db.close();
  });

  test('setupFirstOwner membuat satu user ber-role owner', () async {
    final userId = await repo.setupFirstOwner(
      username: 'sari',
      pinHash: 'hash',
      salt: 'salt',
    );

    final users = await db.select(db.users).get();
    expect(users, hasLength(1));
    expect(users.single.id, userId);
    expect(users.single.username, 'sari');
    expect(users.single.role, 'owner');
  });

  test('hasAnyUser membedakan pemasangan baru dari yang sudah dipakai',
      () async {
    expect(await repo.hasAnyUser(), isFalse,
        reason: 'belum ada user — ini pemasangan baru');

    await repo.setupFirstOwner(
      username: 'sari',
      pinHash: 'hash',
      salt: 'salt',
    );

    expect(await repo.hasAnyUser(), isTrue);
  });

  test('username yang sama ditolak', () async {
    await repo.setupFirstOwner(
      username: 'sari',
      pinHash: 'hash',
      salt: 'salt',
    );

    await expectLater(
      repo.setupFirstOwner(
        username: 'sari',
        pinHash: 'hash-lain',
        salt: 'salt-lain',
      ),
      throwsA(anything),
      reason: 'username unik — dua akun dengan nama sama harus ditolak',
    );
  });
}
