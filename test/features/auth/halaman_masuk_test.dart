import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/recovery/pages/owner_recovery_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Halaman Login dan Reset PIN (desain): galat sebaris, bukan toast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthRepository repo;
  const pin = '112233';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    repo = AuthRepository(db);
    final salt = CryptoUtils.generateSalt();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('o-1'),
            username: 'owner',
            pinHash: CryptoUtils.hashPin(pin, salt),
            salt: salt,
            role: 'owner',
          ),
        );
  });
  tearDown(() async {
    SessionManager.dbOverride = null;
    await db.close();
  });

  void layarHp(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> tunggu(WidgetTester t, [int ms = 80]) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump();
  }

  Future<void> lepas(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  Finder kolom(int i) => find.byType(TextField).at(i);

  /// Di HP kecil tombolnya di bawah layar: digulir dulu, baru ditekan.
  Future<void> tekan(WidgetTester t, String teks) async {
    await t.ensureVisible(find.text(teks));
    await t.pump();
    await t.tap(find.text(teks));
  }

  group('login', () {
    Future<void> buka(WidgetTester t) async {
      layarHp(t);
      await t.pumpWidget(MaterialApp(home: LoginPage(repo: repo)));
      await t.pump();
    }

    testWidgets('tampilan desain, tanpa tombol pilih akun', (t) async {
      await buka(t);
      expect(find.text('Login to Access Your'), findsOneWidget);
      expect(find.text('Teras Inn'), findsOneWidget);
      expect(find.text('Lupa PIN Owner?'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      await lepas(t);
    });

    testWidgets('kosong dan PIN pendek ditolak sebaris; mengetik menghapus '
        'galat', (t) async {
      await buka(t);
      await tekan(t, 'Masuk');
      await t.pump();
      expect(find.text('Username wajib diisi'), findsOneWidget);

      await t.enterText(kolom(0), 'owner');
      await t.pump();
      expect(find.text('Username wajib diisi'), findsNothing);

      await t.enterText(kolom(1), '123');
      await tekan(t, 'Masuk');
      await t.pump();
      expect(find.text('PIN harus 6 digit'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('PIN salah: "Username atau PIN salah"', (t) async {
      await buka(t);
      await t.enterText(kolom(0), 'owner');
      await t.enterText(kolom(1), '999999');
      await tekan(t, 'Masuk');
      await tunggu(t, 300);
      expect(find.text('Username atau PIN salah'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('akun dinonaktifkan: pesannya tampil sebaris', (t) async {
      await t.runAsync(
        () => (db.update(db.users)..where((u) => u.id.equals('o-1'))).write(
          const UsersCompanion(isActive: Value(false)),
        ),
      );
      await buka(t);
      await t.enterText(kolom(0), 'owner');
      await t.enterText(kolom(1), pin);
      await tekan(t, 'Masuk');
      await tunggu(t, 200);
      expect(
        find.text('Akun Anda dinonaktifkan oleh pemilik.'),
        findsOneWidget,
      );
      await lepas(t);
    });

    testWidgets('tombol mata menampilkan PIN', (t) async {
      await buka(t);
      TextField pinField() => t.widget<TextField>(kolom(1));
      expect(pinField().obscureText, isTrue);
      await t.tap(find.bySemanticsLabel('Tampilkan PIN'));
      await t.pump();
      expect(pinField().obscureText, isFalse);
      await lepas(t);
    });

    testWidgets('"Lupa PIN Owner?" membuka Reset PIN, kembali menutupnya', (
      t,
    ) async {
      await buka(t);
      await t.tap(find.text('Lupa PIN Owner?'));
      await t.pumpAndSettle();
      expect(find.text('Reset PIN to Access Your'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Kembali'));
      await t.pumpAndSettle();
      expect(find.text('Login to Access Your'), findsOneWidget);
      await lepas(t);
    });
  });

  group('reset PIN', () {
    late String kodeRecovery;

    setUp(() async {
      kodeRecovery = await repo.generateAndStoreRecoveryCodeForOwner('o-1');
    });

    Future<void> buka(WidgetTester t) async {
      layarHp(t);
      await t.pumpWidget(MaterialApp(home: OwnerRecoveryPage(repo: repo)));
      await tunggu(t);
    }

    testWidgets('PIN tidak cocok ditolak sebelum menyentuh database', (
      t,
    ) async {
      await buka(t);
      await t.enterText(kolom(0), kodeRecovery);
      await t.enterText(kolom(1), '445566');
      await t.enterText(kolom(2), '445567');
      await tekan(t, 'Reset PIN');
      await t.pump();
      expect(find.text('PIN tidak cocok'), findsOneWidget);
      final owner = await t.runAsync(
        () =>
            (db.select(db.users)..where((u) => u.id.equals('o-1'))).getSingle(),
      );
      expect(owner!.recoveryAttempts, 0);
      await lepas(t);
    });

    testWidgets('kode salah: "Kode recovery tidak valid" (bukan bahasa '
        'Inggris)', (t) async {
      await buka(t);
      await t.enterText(kolom(0), 'AAAA-BBBB-CCCC-DDDD');
      await t.enterText(kolom(1), '445566');
      await t.enterText(kolom(2), '445566');
      await tekan(t, 'Reset PIN');
      await tunggu(t, 300);
      expect(find.text('Kode recovery tidak valid'), findsOneWidget);
      expect(find.textContaining('Invalid'), findsNothing);
      await lepas(t);
    });

    testWidgets('lima kali salah: terkunci dengan hitung mundur', (t) async {
      await buka(t);
      await t.enterText(kolom(0), 'AAAA-BBBB-CCCC-DDDD');
      await t.enterText(kolom(1), '445566');
      await t.enterText(kolom(2), '445566');
      for (var i = 0; i < 5; i++) {
        await tekan(t, 'Reset PIN');
        await tunggu(t, 300);
      }
      expect(
        find.textContaining('Terlalu banyak percobaan. Tunggu'),
        findsOneWidget,
      );
      expect(find.textContaining('detik…'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('kode benar: PIN berganti, halaman kode recovery baru', (
      t,
    ) async {
      await buka(t);
      await t.enterText(kolom(0), kodeRecovery);
      await t.enterText(kolom(1), '445566');
      await t.enterText(kolom(2), '445566');
      await tekan(t, 'Reset PIN');
      await tunggu(t, 600);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Kode Recovery Owner'), findsOneWidget);
      final sesi = await t.runAsync(
        () => repo.login(username: 'owner', pin: '445566'),
      );
      expect(sesi, isNotNull);
      await lepas(t);
    });
  });
}
