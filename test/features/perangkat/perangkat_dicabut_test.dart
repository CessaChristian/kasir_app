import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/app/app_shell.dart';
import 'package:kasir_app/app/penjaga_perangkat.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HP yang DICABUT tetap terkunci walau aplikasinya dibuka ulang tanpa
/// internet, dan tidak bisa mengaktifkan dirinya dengan kunci (revisi QA
/// B3/B4). HP yang DILUPAKAN boleh mendaftar ulang.
class _RepoTiruan extends PerangkatRepository {
  _RepoTiruan() : super.untukTest();

  StatusPerangkatIni jawaban = StatusPerangkatIni.takDiketahui;

  @override
  Future<StatusPerangkatIni> statusSaya() async => jawaban;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('tanda dicabut tersimpan', () {
    test('dicabut → disimpan; dibuka ulang offline → tetap dicabut', () async {
      final repo = _RepoTiruan()..jawaban = StatusPerangkatIni.dicabut;
      await repo.periksaStatusSaya();
      expect(repo.dicabut.value, isTrue);

      // Aplikasi dibuka ulang, internet mati.
      final dibukaUlang = _RepoTiruan();
      await dibukaUlang.muatTandaDicabut();
      expect(dibukaUlang.dicabut.value, isTrue);
      await dibukaUlang.periksaStatusSaya(); // takDiketahui
      expect(dibukaUlang.dicabut.value, isTrue,
          reason: 'jawaban "tidak tahu" dulu justru menghapus tandanya');
    });

    test('dipulihkan pemilik → tandanya dilepas', () async {
      final repo = _RepoTiruan()..jawaban = StatusPerangkatIni.dicabut;
      await repo.periksaStatusSaya();
      repo.jawaban = StatusPerangkatIni.aktif;
      await repo.periksaStatusSaya();
      expect(repo.dicabut.value, isFalse);
      final dibukaUlang = _RepoTiruan();
      await dibukaUlang.muatTandaDicabut();
      expect(dibukaUlang.dicabut.value, isFalse);
    });

    test('dilupakan (identitas ditolak) → tanda dicabut dilepas, boleh '
        'mendaftar ulang', () async {
      final repo = _RepoTiruan()..jawaban = StatusPerangkatIni.dicabut;
      await repo.periksaStatusSaya();
      await repo.tandaiIdentitasHilang();
      expect((repo.dicabut.value, repo.identitasHilang.value), (false, true));
      final dibukaUlang = _RepoTiruan();
      await dibukaUlang.muatTandaDicabut();
      expect(dibukaUlang.dicabut.value, isFalse,
          reason: 'kalau tersimpan, HP yang dilupakan terkunci selamanya');
    });
  });

  group('PenjagaPerangkat', () {
    final p = PerangkatRepository.instance;
    tearDown(() {
      p.dicabut.value = false;
      p.identitasHilang.value = false;
      p.belumTerdaftar.value = false;
    });

    Future<void> pasang(WidgetTester t) => t.pumpWidget(const MaterialApp(
          home: PenjagaPerangkat(child: Text('Halaman Login')),
        ));

    testWidgets('normal: alur biasa', (t) async {
      await pasang(t);
      expect(find.text('Halaman Login'), findsOneWidget);
    });

    testWidgets('dicabut: layar "dicabut pemilik" TANPA kolom kunci', (t) async {
      p.dicabut.value = true;
      await pasang(t);
      expect(find.text('HP ini dicabut pemilik'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Periksa lagi'), findsOneWidget);
    });

    testWidgets('dipulihkan selagi layar dicabut terbuka: langsung kembali', (
      t,
    ) async {
      p.dicabut.value = true;
      await pasang(t);
      p.dicabut.value = false;
      await t.pump();
      expect(find.text('Halaman Login'), findsOneWidget);
    });

    testWidgets('dilupakan: Daftarkan Perangkat dengan identitas baru', (
      t,
    ) async {
      p.identitasHilang.value = true;
      await pasang(t);
      expect(find.text('Daftarkan Perangkat'), findsWidgets);
      expect(find.text('Lengkapi Pendaftaran'), findsNothing);
    });

    testWidgets('belum terdaftar (identitas ada): Lengkapi Pendaftaran', (
      t,
    ) async {
      p.belumTerdaftar.value = true;
      await pasang(t);
      expect(find.text('Lengkapi Pendaftaran'), findsOneWidget);
    });
  });

  testWidgets('Periksa lagi tanpa internet: diberi tahu, tetap terkunci', (
    t,
  ) async {
    await t.pumpWidget(MaterialApp(
      home: PerangkatDicabutPage(periksa: () async => false),
    ));
    await t.tap(find.text('Periksa lagi'));
    await t.pumpAndSettle();
    expect(find.textContaining('Tidak tersambung'), findsOneWidget);
  });

  test('sesudah login pun ada yang menanggapi tanda dicabut', () {
    // Dulu penjaga hanya hidup di halaman awal, dan halaman login
    // menggantinya — HP yang dicabut tetap bisa berjualan sampai aplikasinya
    // dibuka ulang (terbukti di emulator 2026-10-24).
    final shell = File('lib/app/app_shell.dart').readAsStringSync();
    expect(shell, contains('p.dicabut, p.identitasHilang, p.belumTerdaftar'));
    expect(shell, contains('ruteMasuk()'));
    final otomatis =
        File('lib/data/sync/sync_otomatis.dart').readAsStringSync();
    expect(otomatis, contains('await periksaPerangkatIni();'),
        reason: 'status dicek tiap menit, bukan tiap sinkron 5 menit');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await PerangkatRepository.instance.muatTandaDicabut();'));
  });

  group('QA S1: dicabut sesudah keluar akun', () {
    final p = PerangkatRepository.instance;
    tearDown(() => p.dicabut.value = false);

    test('setiap jalan ke halaman Login lewat penjaga perangkat', () {
      // Kasir Keluar Akun → owner mencabut HP → halaman Login polos tidak
      // menanggapi tandanya, kasir login lagi dan berjualan.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        expect(f.readAsStringSync(), isNot(contains('=> const LoginPage()')),
            reason: '${f.path}: pakai ruteMasuk()');
      }
    });

    testWidgets('ruteMasuk() saat HP dicabut: layar dicabut', (t) async {
      p.dicabut.value = true;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(ruteMasuk()),
            child: const Text('keluar'),
          ),
        ),
      ));
      await t.tap(find.text('keluar'));
      await t.pumpAndSettle();
      expect(find.text('HP ini dicabut pemilik'), findsOneWidget);
    });

    testWidgets('AppShell dibangun saat HP SUDAH dicabut: tetap terkunci', (
      t,
    ) async {
      // Tandanya sudah menyala sebelum login, jadi tidak ada "perubahan"
      // yang didengar AppShell.
      SharedPreferences.setMockInitialValues({});
      p.dicabut.value = true;
      await t.pumpWidget(const MaterialApp(home: AppShell()));
      await t.pumpAndSettle();
      expect(find.text('HP ini dicabut pemilik'), findsOneWidget);
    });
  });
}
