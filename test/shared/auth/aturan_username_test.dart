import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/aturan_username.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Username selalu huruf kecil (keputusan owner 2026-10-28): saat diketik,
/// saat dibandingkan, dan saat login.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isian', () {
    TextEditingValue ketik(String teks, [int? kursor]) =>
        const UsernameInputFormatter().formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: teks,
            selection: TextSelection.collapsed(offset: kursor ?? teks.length),
          ),
        );

    test('Caps Lock menyala: tetap jadi huruf kecil', () {
      expect(ketik('SARI').text, 'sari');
      expect(ketik('Budi.W_2').text, 'budi.w_2');
    });

    test('karakter lain dibuang, termasuk lewat tempel', () {
      expect(ketik('sa ri~1!').text, 'sari1');
      expect(ketik('sаri').text, 'sri', reason: 'а Cyrillic dibuang');
      expect(ketik('sa​ri').text, 'sari');
    });

    test('paling panjang 20 huruf', () {
      expect(ketik('a' * 25).text, 'a' * panjangUsernameMaks);
    });

    test('kursor ikut bergeser sesuai huruf yang dibuang', () {
      // "s ar|i" → spasi dibuang → "sar|i".
      expect(ketik('s ari', 4).selection.baseOffset, 3);
    });
  });

  group('login', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SessionManager.dbOverride = db;
      final salt = CryptoUtils.generateSalt();
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('k-1'),
              username: 'sari',
              pinHash: CryptoUtils.hashPin('246810', salt),
              salt: salt,
              role: 'cashier',
            ),
          );
    });
    tearDown(() async {
      await SessionManager.instance.clearSession();
      SessionManager.dbOverride = null;
      await db.close();
    });

    test('harus persis huruf kecil: SARI bukan sari', () async {
      final repo = AuthRepository(db);
      expect(await repo.login(username: 'SARI', pin: '246810'), isNull);
      expect(await repo.login(username: 'Sari', pin: '246810'), isNull);
      final sesi = await repo.login(username: ' sari ', pin: '246810');
      expect(sesi?.userId, 'k-1');
    });

    testWidgets('kolom username di halaman login memaksa huruf kecil', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.enterText(find.byType(TextField).first, 'SARI');
      expect(find.text('sari'), findsOneWidget);
      expect(find.text('SARI'), findsNothing);
    });
  });

  test('owner pertama memakai aturan yang sama', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    addTearDown(() async {
      SessionManager.dbOverride = null;
      await db.close();
    });
    await expectLater(
      AuthRepository(db).bootstrapOwner(username: 'own~er', pin: '135790'),
      throwsArgumentError,
    );
  });
}
