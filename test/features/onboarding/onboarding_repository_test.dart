import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
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

  Future<({User owner, String kodeRecovery})> buat(String nama) =>
      AuthRepository(db).buatOwnerPertama(username: nama, pin: '135790');

  test('owner pertama dibuat bersama kode recovery-nya', () async {
    final hasil = await buat('sari');
    final users = await db.select(db.users).get();
    expect(users, hasLength(1));
    expect(users.single.id, hasil.owner.id);
    expect(users.single.role, 'owner');
    expect(users.single.recoveryHash, isNotNull);
    expect(hasil.kodeRecovery, isNotEmpty);
  });

  test('hasAnyUser membedakan pemasangan baru dari yang sudah dipakai',
      () async {
    expect(await repo.hasAnyUser(), isFalse,
        reason: 'belum ada user — ini pemasangan baru');
    await buat('sari');
    expect(await repo.hasAnyUser(), isTrue);
  });

  test('owner kedua ditolak — dulu jalur onboarding bisa membuat dua',
      () async {
    await buat('sari');
    await expectLater(buat('budi'), throwsA(isA<StateError>()));
    expect(await db.select(db.users).get(), hasLength(1));
  });

  test('review 3 Nov: kode recovery gagal dibuat → akun owner ikut batal, '
      'jadi bisa dicoba lagi', () async {
    // Kolom recovery dirusak supaya langkah kedua gagal.
    await db.customStatement(
      "CREATE TRIGGER gagal BEFORE UPDATE OF recovery_hash ON users "
      "BEGIN SELECT RAISE(ABORT, 'disk penuh'); END",
    );
    await expectLater(buat('sari'), throwsA(anything));
    expect(await db.select(db.users).get(), isEmpty,
        reason: 'dulu akunnya tertinggal tanpa kode recovery');

    await db.customStatement('DROP TRIGGER gagal');
    final ulang = await buat('sari');
    expect(ulang.kodeRecovery, isNotEmpty);
  });
}
