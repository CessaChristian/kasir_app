import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/printer/data/layanan_printer.dart';
import 'package:kasir_app/features/printer/pages/printer_page.dart';
import 'package:kasir_app/shared/ui/bingkai_halaman.dart';
import 'package:kasir_app/shared/ui/segarkan/pengendali_segarkan.dart';
import 'package:kasir_app/shared/ui/segarkan/tombol_segarkan.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tiruan implements SaluranPrinter {
  var printer = <PrinterTerpasang>[];
  var dibaca = 0;
  var menyala = true;
  var izinDiminta = 0;
  var izin = true;

  @override
  Future<bool> bluetoothNyala() async => true;
  @override
  Future<bool> izinAda() async {
    izinDiminta++;
    return izin;
  }
  /// Bacaan daftar berikutnya ditahan sampai ini diselesaikan.
  Completer<List<PrinterTerpasang>>? tahan;

  @override
  Future<List<PrinterTerpasang>> terpasang() async {
    dibaca++;
    final c = tahan;
    if (c != null) {
      tahan = null;
      return c.future;
    }
    return printer;
  }

  @override
  Future<void> bukaPengaturanBluetooth() async {}
  var izinDibuka = 0;
  @override
  Future<void> bukaPengaturanIzin() async => izinDibuka++;
  @override
  Future<bool> tersambung() async => false;
  @override
  Future<bool> sambung(String mac) async => menyala;
  @override
  Future<bool> kirim(List<int> bytes) async => true;
  @override
  Future<void> putus() async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  late _Tiruan t;
  late Completer<HasilSync> sinkron;

  Future<void> pasang(
    WidgetTester tester, {
    bool izin = true,
    List<PrinterTerpasang> printer = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    t = _Tiruan()
      ..izin = izin
      ..printer = printer;
    sinkron = Completer<HasilSync>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BingkaiHalaman(
          judul: 'Printer Struk',
          pengendaliUntukTest: PengendaliSegarkan(
            jalankan: () => sinkron.future,
            batasTersambungUji: const Duration(seconds: 30),
          ),
          child: PrinterPage(layanan: LayananPrinter.untukTest(t)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('belum ada printer → keadaan kosong dengan panduan', (
    tester,
  ) async {
    await pasang(tester);
    expect(find.text('Belum ada printer'), findsOneWidget);
    expect(find.text('Buka Pengaturan Bluetooth'), findsOneWidget);
    expect(find.text('80 mm'), findsNothing);
  });

  testWidgets('tombol segarkan di header ikut memuat ulang daftar printer; '
      'printer satu-satunya langsung dipakai', (tester) async {
    await pasang(tester);
    expect(t.dibaca, 1);

    // Printer baru dipasangkan di Pengaturan Bluetooth.
    t.printer = [(nama: 'RPP02N', mac: '86:67:7A:80:4E:3D')];
    await tester.tap(find.byType(TombolSegarkan));
    await tester.pump();
    await tester.pump();
    expect(t.dibaca, 2, reason: 'tidak menunggu sinkron server selesai');

    sinkron.complete(const HasilSync());
    await tester.pumpAndSettle();
    expect(find.text('RPP02N'), findsOneWidget);
    expect(find.text('Tersambung · siap mencetak'), findsOneWidget);
    expect((await LayananPrinter.untukTest(t).muat()).mac,
        '86:67:7A:80:4E:3D');
  });

  testWidgets('printer yang dipakai menyala: "Tersambung · siap mencetak"', (
    tester,
  ) async {
    await pasang(tester);
    t.printer = [(nama: 'RPP02N', mac: '86:67:7A:80:4E:3D')];
    await tester.tap(find.byType(TombolSegarkan));
    sinkron.complete(const HasilSync());
    await tester.pumpAndSettle();
    expect(find.text('Tersambung · siap mencetak'), findsOneWidget);
  });

  testWidgets('printer mati: "Tidak terhubung", Coba lagi memeriksa ulang', (
    tester,
  ) async {
    await pasang(tester);
    t
      ..printer = [(nama: 'RPP02N', mac: '86:67:7A:80:4E:3D')]
      ..menyala = false;
    await tester.tap(find.byType(TombolSegarkan));
    sinkron.complete(const HasilSync());
    await tester.pumpAndSettle();
    expect(find.textContaining('Tidak terhubung'), findsOneWidget);
    expect(find.text('RPP02N'), findsOneWidget,
        reason: 'tetap di daftar — memang masih dipasangkan');

    t.menyala = true;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Tersambung · siap mencetak'), findsOneWidget);
  });

  testWidgets('kembali aktif sesudah popup izin TIDAK memuat ulang (izin '
      'tidak diminta berulang); sesudah Pengaturan Bluetooth memuat ulang', (
    tester,
  ) async {
    await pasang(tester);
    final awal = t.izinDiminta;
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(t.izinDiminta, awal, reason: 'popup izin: hanya inactive');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(t.izinDiminta, awal + 1, reason: 'kembali dari Pengaturan');
  });

  testWidgets('izin Bluetooth ditolak: Beri izin + jalan ke Pengaturan Izin '
      '(popup tidak muncul lagi sesudah ditolak dua kali)', (tester) async {
    await pasang(tester, izin: false);
    expect(find.text('Izin Bluetooth dibutuhkan'), findsOneWidget);
    expect(find.text('Beri izin'), findsOneWidget);
    await tester.tap(find.text('Popup izin tidak muncul? Buka Pengaturan Izin'));
    await tester.pump();
    expect(t.izinDibuka, 1);
  });

  testWidgets('tanpa keterangan ukuran kertas', (tester) async {
    await pasang(tester);
    expect(find.textContaining('58 mm'), findsNothing);
  });

  const a = (nama: 'RPP02N', mac: 'AA:AA');
  const b = (nama: 'Printer Dapur', mac: 'BB:BB');

  testWidgets('dua printer terpasang: tidak ada yang dipilih otomatis, '
      'kasir memilih sendiri dan bisa pindah', (tester) async {
    await pasang(tester, printer: [a, b]);
    expect(find.text('Ketuk untuk memakai'), findsNWidgets(2));

    await tester.tap(find.text('Printer Dapur'));
    await tester.pumpAndSettle();
    expect((await LayananPrinter.untukTest(t).muat()).mac, 'BB:BB');
    expect(find.text('Tersambung · siap mencetak'), findsOneWidget);
    expect(find.text('Ketuk untuk memakai'), findsOneWidget,
        reason: 'RPP02N masih bisa dipilih');

    await tester.tap(find.text('RPP02N'));
    await tester.pumpAndSettle();
    expect((await LayananPrinter.untukTest(t).muat()).mac, 'AA:AA');
  });

  testWidgets('daftar lama yang telat datang tidak menimpa daftar baru dan '
      'printer yang baru dipilih', (tester) async {
    await pasang(tester);

    // Muatan pertama (sebelum printer kedua dipasangkan) tertahan. Waktu
    // dimajukan sedikit-sedikit: bacaan daftar menyerah sesudah 7 detik.
    Future<void> jalan() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final lama = t.tahan = Completer();
    await tester.tap(find.byType(TombolSegarkan));
    await jalan();
    sinkron.complete(const HasilSync());
    await jalan();

    // Muatan berikutnya: dua printer; kasir memilih Printer Dapur.
    t.printer = [a, b];
    await tester.tap(find.byType(TombolSegarkan));
    await jalan();
    await tester.tap(find.text('Printer Dapur'));
    await jalan();

    // Daftar lama (satu printer) baru datang.
    lama.complete([a]);
    await jalan();
    expect((await LayananPrinter.untukTest(t).muat()).mac, 'BB:BB',
        reason: 'dulu ditimpa RPP02N karena daftar lama isinya satu');
    expect(find.text('RPP02N'), findsOneWidget);
    expect(find.text('Printer Dapur'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
