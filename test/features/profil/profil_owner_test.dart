import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/recovery/pages/save_recovery_code_page.dart';
import 'package:kasir_app/features/auth/recovery/widgets/lembar_kode_recovery.dart';
import 'package:kasir_app/features/auth/repositories/auth_repository.dart';
import 'package:kasir_app/features/profil/pages/profil_owner_page.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/constants/app_constants.dart';
import 'package:kasir_app/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profil owner (desain) beserta alur Kode Recovery.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void layarHp(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  test('versi di Profil sama dengan version di pubspec.yaml', () {
    final baris = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final versi = baris.split(':').last.trim().split('+').first;
    expect(AppConstants.versiAplikasi, versi);
  });

  testWidgets('isi dan urutan menu Profil sesuai desain', (t) async {
    // Layar panjang supaya seluruh daftar tergambar sekaligus.
    t.view.physicalSize = const Size(1080, 5400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'o',
        username: 'owner',
        role: 'owner',
        shiftId: null,
        permissions: const [],
      ),
    );
    addTearDown(SessionManager.instance.clearSession);

    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfilOwnerPage())),
    );
    await t.pump();

    final urutan = [
      'owner',
      'Owner',
      'MENU LAINNYA',
      'Laporan',
      'Riwayat Shift',
      'Kategori',
      'MANAJEMEN',
      'Kelola Kasir',
      'PERANGKAT & AKUN',
      'Printer Struk',
      'Perangkat Terdaftar',
      'Kode Recovery',
      'Keluar',
      'Teras Inn POS · v${AppConstants.versiAplikasi}',
    ];
    double y(String teks) => t.getTopLeft(find.text(teks)).dy;
    for (var i = 1; i < urutan.length; i++) {
      expect(
        y(urutan[i]),
        greaterThanOrEqualTo(y(urutan[i - 1])),
        reason: '"${urutan[i]}" harus di bawah "${urutan[i - 1]}"',
      );
    }
    expect(find.text('O'), findsOneWidget, reason: 'inisial di kartu akun');

    // Printer belum ada: diketuk tidak membuka apa pun dan tanpa pesan.
    await t.tap(find.text('Printer Struk'));
    await t.pumpAndSettle();
    expect(find.byType(ProfilOwnerPage), findsOneWidget);
    expect(find.textContaining('belum tersedia'), findsNothing);
  });

  group('Kode Recovery', () {
    late AppDatabase db;
    const pin = '135790';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final garam = CryptoUtils.generateSalt();
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('o'),
              username: 'owner',
              pinHash: CryptoUtils.hashPin(pin, garam),
              salt: garam,
              role: 'owner',
            ),
          );
    });
    tearDown(() => db.close());

    testWidgets('PIN salah tetap di lembar; PIN benar memberi kode baru', (
      t,
    ) async {
      layarHp(t);
      String? hasil;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => hasil = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    LembarPerbaruiRecovery(authRepo: AuthRepository(db)),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      );
      await t.tap(find.text('buka'));
      await t.pumpAndSettle();
      expect(find.text('Perbarui Kode Recovery'), findsOneWidget);

      final isian = find.byKey(const Key('isian-pin-recovery'));
      await t.enterText(isian, '111111');
      await t.tap(find.text('Buat Kode Baru'));
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await t.pumpAndSettle();
      expect(
        find.text('Perbarui Kode Recovery'),
        findsOneWidget,
        reason: 'PIN salah: lembar tidak tertutup',
      );
      expect(hasil, isNull);

      await t.enterText(isian, pin);
      await t.tap(find.text('Buat Kode Baru'));
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await t.pumpAndSettle();
      expect(hasil, isNotNull);
      expect(hasil!.replaceAll('-', ''), hasLength(16));
    });
  });

  testWidgets('halaman kode: tombol lanjut baru aktif setelah dicentang', (
    t,
  ) async {
    layarHp(t);
    var selesai = false;
    await t.pumpWidget(
      MaterialApp(
        home: SaveRecoveryCodePage(
          recoveryCode: 'ABCD1234EFGH5678',
          onComplete: (_) => selesai = true,
        ),
      ),
    );
    expect(find.text('ABCD-1234-EFGH-5678'), findsOneWidget);

    final tombol = find.widgetWithText(
      FilledButton,
      'Saya Mengerti, Lanjutkan',
    );
    expect(t.widget<FilledButton>(tombol).onPressed, isNull);
    await t.tap(find.text('Saya sudah menyimpan kode recovery dengan aman'));
    await t.pump();
    await t.tap(tombol);
    expect(selesai, isTrue);
  });
}
