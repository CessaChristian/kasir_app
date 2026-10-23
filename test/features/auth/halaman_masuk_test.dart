import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/pages/login_page.dart';
import 'package:kasir_app/features/auth/recovery/pages/owner_recovery_page.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Halaman Login dan Reset PIN (desain): galat sebaris, bukan toast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Masuk yang berhasil membuka halaman kasir, yang memformat tanggal.
  setUpAll(() => initializeDateFormatting('id_ID'));

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

  /// Tunggu sampai tombol tidak lagi "Memeriksa…". PIN diperiksa di isolate
  /// lain, kadang beberapa kali berturut-turut (cek PIN lalu buat hash baru)
  /// — tiap langkah butuh waktu nyata, jadi ditunggu sedikit-sedikit.
  Future<void> tungguSelesai(WidgetTester t) async {
    await t.pump();
    final memeriksa = find.text('Memeriksa…');
    for (var i = 0; i < 300 && memeriksa.evaluate().isNotEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump();
    }
    await tunggu(t, 30);
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

  test('login tidak menahan layar selama PIN diperiksa', () async {
    var detak = 0;
    final jam = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => detak++,
    );
    final sesi = await repo.login(username: 'owner', pin: pin);
    jam.cancel();
    expect(sesi, isNotNull);
    expect(detak, greaterThanOrEqualTo(5),
        reason: 'PIN diperiksa di isolate utama = tombol "Memeriksa…" baru '
            'tergambar setelah akun diterima');
  });

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
      await tungguSelesai(t);
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
      // Pesannya baru keluar sesudah PIN diperiksa — sebelum itu, username
      // nonaktif dijawab sama seperti PIN salah (revisi QA B7b).
      await tungguSelesai(t);
      expect(
        find.text('Akun Anda dinonaktifkan oleh pemilik.'),
        findsOneWidget,
      );
      await lepas(t);
    });

    testWidgets('masuk melanjutkan shift: server langsung diberi tahu, '
        'tanpa menunggu sinkron 5 menit', (t) async {
      final dilapor = <String?>[];
      await t.runAsync(() async {
        final salt = CryptoUtils.generateSalt();
        await db.into(db.users).insert(UsersCompanion.insert(
              id: const Value('k-1'),
              username: 'budi',
              pinHash: CryptoUtils.hashPin(pin, salt),
              salt: salt,
              role: 'cashier',
            ));
        await db.into(db.shifts).insert(ShiftsCompanion.insert(
              id: const Value('s-1'),
              userId: 'k-1',
            ));
      });
      layarHp(t);
      await t.pumpWidget(MaterialApp(
        home: LoginPage(
          repo: AuthRepository(
            db,
            tungguSinkron: () async {},
            lapor: (shiftId) async => dilapor.add(shiftId),
          ),
        ),
      ));
      await t.pump();
      await t.enterText(kolom(0), 'budi');
      await t.enterText(kolom(1), pin);
      await tekan(t, 'Masuk');
      await tungguSelesai(t);
      expect(SessionManager.instance.currentSession?.shiftId, 's-1');
      expect(dilapor, ['s-1']);
      await lepas(t);
      await SessionManager.instance.clearSession();
    });

    testWidgets('Masuk: tombol langsung "Memeriksa…" sampai PIN selesai '
        'diperiksa; Enter berkali-kali tetap sekali', (t) async {
      final tahan = _RepoTahan(db);
      layarHp(t);
      await t.pumpWidget(MaterialApp(home: LoginPage(repo: tahan)));
      await t.pump();
      await t.enterText(kolom(0), 'owner');
      await t.enterText(kolom(1), '999999');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Memeriksa…'), findsOneWidget);

      // Keyboard menutup sesudah Enter; kasir mengetuk kolom PIN lagi dan
      // menekan Enter selagi masih memeriksa.
      for (var i = 0; i < 2; i++) {
        await t.showKeyboard(kolom(1));
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump();
      }
      expect(tahan.dipanggil, 1);

      tahan.hasil.complete(null);
      await t.pump();
      expect(find.text('Masuk'), findsOneWidget);
      expect(find.text('Username atau PIN salah'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('tombol mata menampilkan PIN', (t) async {
      await buka(t);
      TextField pinField() => t.widget<TextField>(kolom(1));
      expect(pinField().obscureText, isTrue);
      expect(pinField().style!.letterSpacing, 4, reason: 'titik PIN renggang');
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
      await tungguSelesai(t);
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
        await tungguSelesai(t);
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
      await tungguSelesai(t);
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

/// Login yang menunggu sampai test memutuskan hasilnya.
class _RepoTahan extends AuthRepository {
  _RepoTahan(super.db);

  var dipanggil = 0;
  final hasil = Completer<AuthSession?>();

  @override
  Future<AuthSession?> login({
    required String username,
    required String pin,
  }) {
    dipanggil++;
    return hasil.future;
  }
}
