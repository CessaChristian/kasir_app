import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/printer/data/struk_cetak.dart';
import 'package:kasir_app/features/profil/pages/info_outlet_page.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/constants/info_nota.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Info Outlet (11 Nov 2026): owner mengganti alamat, nomor HP, dan WiFi di
/// nota; tersinkron lewat tabel `info_toko`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUpAll(() => initializeDateFormatting('id_ID', null));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    InfoNota.kini.value = InfoNota.bawaan;
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
    InfoNota.kini.value = InfoNota.bawaan;
  });

  Future<void> masuk(String peran) => SessionManager.instance.setSession(
    AuthSession.create(
      userId: 'u',
      username: peran,
      role: peran,
      shiftId: null,
      permissions: const [],
    ),
  );

  const baru = InfoNota(
    alamat: 'Jl. Diponegoro 12',
    noHp: '0812-3456',
    wifiNama: 'TERAS BARU',
    wifiSandi: 'rahasia 123',
  );

  Future<void> simpan(InfoNota i) => db.simpanInfoToko(
    alamat: i.alamat,
    noHp: i.noHp,
    wifiNama: i.wifiNama,
    wifiSandi: i.wifiSandi,
  );

  Map<String, dynamic> barisServer(String alamat, DateTime cap) => {
    'id': idInfoToko,
    'alamat': alamat,
    'no_hp': '0811',
    'wifi_nama': '',
    'wifi_sandi': '',
    'updated_at': cap.toUtc().toIso8601String(),
    'server_urut': cap.toUtc().toIso8601String(),
  };

  group('aturan isian', () {
    test('dirapikan: spasi tepi dan spasi beruntun tidak dihitung beda', () {
      final a = InfoNota.rapikan(
        alamat: '  Jl.  Kemiri   Candi ',
        noHp: ' 087859665084 ',
        wifiNama: 'TERAS INN ',
        wifiSandi: ' terasinspirasi',
      );
      expect(a, InfoNota.bawaan);
      expect(a.sah, isTrue);
    });

    test('alamat & nomor HP wajib; huruf yang tidak tercetak ditolak', () {
      InfoNota i({
        String alamat = 'Jl. A',
        String hp = '0812',
        String w = '',
      }) => InfoNota(alamat: alamat, noHp: hp, wifiNama: w, wifiSandi: '');
      expect(i(alamat: '').galatAlamat, 'Alamat wajib diisi');
      expect(i(alamat: 'Jl. Café').galatAlamat, isNotNull);
      expect(i(alamat: 'a' * 65).galatAlamat, isNotNull);
      expect(i(hp: '').galatNoHp, 'Nomor HP wajib diisi');
      expect(i(hp: '0812abc').galatNoHp, isNotNull);
      expect(i(hp: '+62 812-3456').galatNoHp, isNull);
      expect(i(w: 'WiFi 📶').galatWifiNama, isNotNull);
      expect(
        const InfoNota(
          alamat: 'Jl. A',
          noHp: '0812',
          wifiNama: '',
          wifiSandi: 'abc',
        ).sah,
        isFalse,
        reason: 'sandi tanpa nama WiFi tidak akan tercetak',
      );
    });
  });

  group('nota cetak', () {
    final waktu = DateTime(2026, 11, 11, 10);
    final tx = Transaction(
      id: 't',
      invoiceNo: 'CS/01/111126/K-0001',
      createdAt: waktu,
      total: 5000,
      paymentMethod: 'qris',
      orderType: 'dine_in',
      updatedAt: waktu,
      syncStatus: 'synced',
    );
    List<String> teks(List<BarisCetak> b) => [for (final x in b) x.teks];

    test('memakai info yang berlaku saat dicetak, juga test print', () {
      InfoNota.kini.value = baru;
      final t = teks(susunStruk(tx: tx, items: const [], namaKasir: 'sari'));
      expect(t.take(2), ['Jl. Diponegoro 12', '0812-3456']);
      expect(t.skip(t.length - 2), [
        'WiFi : TERAS BARU',
        'Password : rahasia 123',
      ]);
      expect(teks(susunTestPrint(namaPrinter: 'P', waktu: waktu)).take(2), [
        'Jl. Diponegoro 12',
        '0812-3456',
      ]);
    });

    test('alamat panjang dibungkus; WiFi kosong tidak dicetak', () {
      final t = teks(
        susunStruk(
          tx: tx,
          items: const [],
          namaKasir: 'sari',
          info: const InfoNota(
            alamat: 'Jl. Jenderal Sudirman No. 123, Salatiga Jawa Tengah',
            noHp: '0812',
            wifiNama: '',
            wifiSandi: '',
          ),
        ),
      );
      expect(t.take(3), [
        'Jl. Jenderal Sudirman No. 123,',
        'Salatiga Jawa Tengah',
        '0812',
      ]);
      expect(
        t.any((b) => b.contains('WiFi') || b.contains('Password')),
        isFalse,
      );
      expect(t.every((b) => b.length <= kolomNota), isTrue);
    });
  });

  group('simpan', () {
    test(
      'hanya owner; tersimpan menunggu kirim dan langsung berlaku',
      () async {
        await masuk('cashier');
        await expectLater(simpan(baru), throwsA(isA<IzinDitolak>()));
        expect(await db.select(db.infoToko).get(), isEmpty);

        await masuk('owner');
        InfoNota.pantau(db);
        await simpan(baru);
        await simpan(baru);
        final b = (await db.select(db.infoToko).get()).single;
        expect((b.id, b.syncStatus), (idInfoToko, 'pending'));
        await pumpEventQueue();
        expect(InfoNota.kini.value, baru);
      },
    );
  });

  group('sinkron', () {
    test(
      'kiriman berisi kolom server; sesudah terkirim tidak pending',
      () async {
        await masuk('owner');
        await simpan(baru);
        final kiriman = <String, List<Map<String, dynamic>>>{};
        final mesin = SyncEngine(db)
          ..pengirimUntukTest = (tabel, baris) async => kiriman[tabel] = baris;
        final (terkirim, gagal) = await mesin.dorongSemua();
        expect(terkirim, 1);
        expect(gagal, isEmpty);
        expect(kiriman['info_toko']!.single, {
          'id': idInfoToko,
          'alamat': 'Jl. Diponegoro 12',
          'no_hp': '0812-3456',
          'wifi_nama': 'TERAS BARU',
          'wifi_sandi': 'rahasia 123',
          'updated_at': isA<String>(),
        });
        expect(
          (await db.select(db.infoToko).get()).single.syncStatus,
          'synced',
        );
      },
    );

    test('tarikan: versi server ditulis, tapi tidak menimpa perubahan HP '
        'ini yang lebih baru', () async {
      final mesin = SyncEngine(db);
      await mesin.gabungkanTabel('info_toko', [
        barisServer('Jl. Server 1', DateTime(2026, 1, 1)),
      ]);
      var b = (await db.select(db.infoToko).get()).single;
      expect((b.alamat, b.syncStatus), ('Jl. Server 1', 'synced'));

      await masuk('owner');
      await simpan(baru);
      await mesin.gabungkanTabel('info_toko', [
        barisServer('Jl. Server 2', DateTime(2026, 6, 1)),
      ]);
      b = (await db.select(db.infoToko).get()).single;
      expect((b.alamat, b.syncStatus), ('Jl. Diponegoro 12', 'pending'));
    });

    test('server belum punya tabelnya: dilewati, tidak dihitung gagal, '
        'perubahan tetap menunggu', () async {
      await masuk('owner');
      await simpan(baru);
      final belumAda = PostgrestException(
        message: "Could not find the table 'public.info_toko'",
        code: 'PGRST205',
      );
      final ditarik = <String>[];
      final mesin = SyncEngine(db)
        ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
          ditarik.add(tabel);
          if (tabel == 'info_toko') throw belumAda;
          return [];
        }
        ..pengirimUntukTest = (tabel, baris) async {
          if (tabel == 'info_toko') throw belumAda;
        };
      await mesin.tarikSemua();
      expect(ditarik, contains('info_toko'));
      final (terkirim, gagal) = await mesin.dorongSemua();
      expect(terkirim, 0);
      expect(gagal, isEmpty);
      expect(mesin.ditolak, 0);
      expect((await db.select(db.infoToko).get()).single.syncStatus, 'pending');
    });

    test('tabel lain yang belum ada tetap galat', () async {
      final mesin = SyncEngine(db)
        ..penarikUntukTest = (tabel, kolom, sejak, setelah, batas) async {
          if (tabel == 'products') {
            throw PostgrestException(message: 'x', code: 'PGRST205');
          }
          return [];
        };
      await expectLater(mesin.tarikSemua(), throwsA(isA<PostgrestException>()));
    });
  });

  test('migrasi v42 → v43: tabel info_toko dibuat, data lama utuh', () async {
    final folder = Directory.systemTemp.createTempSync('uji_v43');
    addTearDown(() => folder.deleteSync(recursive: true));
    final jalur = '${folder.path}/v42.sqlite';

    final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    await lama
        .into(lama.products)
        .insert(
          ProductsCompanion.insert(
            id: const Value('p-1'),
            name: 'Kopi',
            price: 1,
          ),
        );
    await lama.close();

    final mentah = sql.sqlite3.open(jalur);
    mentah.execute('DROP TABLE info_toko');
    mentah.execute('PRAGMA user_version = 42');
    mentah.close();

    final baruDb = AppDatabase.forTesting(NativeDatabase(File(jalur)));
    addTearDown(baruDb.close);
    expect((await baruDb.select(baruDb.products).get()).single.name, 'Kopi');
    expect(await baruDb.select(baruDb.infoToko).get(), isEmpty);
  });

  group('halaman', () {
    final tombol = find.text('Simpan Perubahan');
    Finder kolom(String kunci) => find.descendant(
      of: find.byKey(ValueKey('kolom_$kunci')),
      matching: find.byType(TextField),
    );

    Future<void> buka(WidgetTester t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.runAsync(() => masuk('owner'));
      await t.pumpWidget(MaterialApp(home: InfoOutletPage(basis: db)));
      await t.pumpAndSettle();
    }

    testWidgets('tombol simpan baru muncul saat isinya berbeda, dan hilang '
        'lagi saat dikembalikan seperti semula', (t) async {
      await buka(t);
      expect(tombol, findsNothing);
      expect(find.text('Jl. Kemiri Candi'), findsWidgets);

      await t.enterText(kolom('alamat'), 'Jl. Kemiri Candi 5');
      await t.pumpAndSettle();
      expect(tombol, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pratinjau_nota')),
          matching: find.text('Jl. Kemiri Candi 5'),
        ),
        findsOneWidget,
        reason: 'pratinjau mengikuti isian',
      );

      // Spasi di ujung bukan perubahan.
      await t.enterText(kolom('alamat'), 'Jl. Kemiri Candi  ');
      await t.pumpAndSettle();
      expect(tombol, findsNothing);
    });

    testWidgets('isian tidak sah: tombol ada tapi tidak bisa ditekan', (
      t,
    ) async {
      await buka(t);
      await t.enterText(kolom('no_hp'), '');
      await t.pumpAndSettle();
      expect(find.text('Nomor HP wajib diisi'), findsOneWidget);
      await t.tap(tombol);
      await t.pumpAndSettle();
      expect(find.text('Simpan info outlet?'), findsNothing);
    });

    testWidgets('sinkron membawa info baru selagi halaman terbuka: kolom '
        'langsung mengikuti', (t) async {
      await buka(t);
      InfoNota.kini.value = baru;
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(kolom('alamat')).controller!.text,
        'Jl. Diponegoro 12',
      );
      expect(
        t.widget<TextField>(kolom('wifi_nama')).controller!.text,
        'TERAS BARU',
      );
      expect(tombol, findsNothing, reason: 'bukan perubahan owner di HP ini');
      expect(find.byKey(const ValueKey('catatan_hp_lain')), findsNothing);
    });

    testWidgets('sinkron tidak menimpa isian yang belum disimpan', (t) async {
      await buka(t);
      await t.enterText(kolom('no_hp'), '0899');
      await t.pumpAndSettle();
      InfoNota.kini.value = baru;
      await t.pumpAndSettle();
      expect(t.widget<TextField>(kolom('no_hp')).controller!.text, '0899');
      expect(
        t.widget<TextField>(kolom('alamat')).controller!.text,
        'Jl. Diponegoro 12',
        reason: 'kolom yang tidak disentuh mengikuti data terbaru',
      );
      expect(find.byKey(const ValueKey('catatan_hp_lain')), findsOneWidget);
      expect(tombol, findsOneWidget);

      // Ringkasan memakai data terbaru sebagai "sebelum".
      await t.tap(tombol);
      await t.pumpAndSettle();
      expect(find.textContaining('No. HP: 0812-3456 → 0899'), findsOneWidget);
    });

    testWidgets('simpan: ringkasan sebelum → sesudah, lalu tersimpan dan '
        'tombol hilang', (t) async {
      await buka(t);
      await t.enterText(kolom('alamat'), 'Jl. Diponegoro 12');
      await t.enterText(kolom('wifi_nama'), '');
      await t.enterText(kolom('wifi_sandi'), '');
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pratinjau_nota')),
          matching: find.textContaining('WiFi'),
        ),
        findsNothing,
      );

      await t.tap(tombol);
      await t.pumpAndSettle();
      expect(find.text('Simpan info outlet?'), findsOneWidget);
      expect(
        find.textContaining('Alamat: Jl. Kemiri Candi → Jl. Diponegoro 12'),
        findsOneWidget,
      );
      expect(find.textContaining('WiFi: TERAS INN → (kosong)'), findsOneWidget);

      await t.tap(find.text('Simpan'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle(const Duration(seconds: 6));
      final b = await t.runAsync(() => db.select(db.infoToko).getSingle());
      expect(
        (b!.alamat, b.wifiNama, b.noHp),
        ('Jl. Diponegoro 12', '', '087859665084'),
      );
      expect(tombol, findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });
  });
}
