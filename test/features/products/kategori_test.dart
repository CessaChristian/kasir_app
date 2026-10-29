import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/products/pages/kategori_page.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/sales/models/saring_kategori.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/constants/category_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Halaman Kategori (v36): semua aksi masuk draf dan baru berlaku saat
/// "Simpan Perubahan"; kategori bisa disembunyikan dari Kasir (produknya
/// tetap tampil); hapus kategori = produknya jadi Tanpa Kategori.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  late AppDatabase db;

  Future<void> masuk(String role, [List<String> izin = const []]) =>
      SessionManager.instance.setSession(
        AuthSession.create(
          userId: role == 'owner' ? 'o-1' : 'k-1',
          username: role,
          role: role,
          shiftId: role == 'cashier' ? 's-1' : null,
          permissions: izin,
        ),
      );

  Future<void> kategori(String id, String nama, {bool tampil = true}) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: Value(id),
          name: nama,
          tampilDiKasir: Value(tampil),
          syncStatus: const Value('synced'),
        ),
      );

  Future<void> produk(String id, String? kategoriId) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: Value(id),
          name: 'Produk $id',
          price: 10000,
          categoryId: Value(kategoriId),
          syncStatus: const Value('synced'),
        ),
      );

  Future<Category> ambil(String id) =>
      (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SessionManager.dbOverride = db;
    await masuk('owner');
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    SessionManager.dbOverride = null;
    await db.close();
  });

  test(
    'migrasi v35 → v36: kolom ada, kategori lama tampil, izin baru',
    () async {
      final folder = Directory.systemTemp.createTempSync('uji_v36');
      addTearDown(() => folder.deleteSync(recursive: true));
      final jalur = '${folder.path}/v35.sqlite';

      final lama = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      await lama
          .into(lama.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('k-kopi'),
              name: 'Kopi',
              syncStatus: const Value('synced'),
            ),
          );
      await lama.close();

      final mentah = sqlite3.open(jalur);
      mentah.execute('ALTER TABLE categories DROP COLUMN tampil_di_kasir');
      mentah.execute(
        "DELETE FROM permissions WHERE code = 'manage_categories'",
      );
      mentah.execute('PRAGMA user_version = 35');
      mentah.close();

      final baru = AppDatabase.forTesting(NativeDatabase(File(jalur)));
      addTearDown(baru.close);
      final k = await baru.select(baru.categories).getSingle();
      expect(k.tampilDiKasir, isTrue);
      expect(k.syncStatus, 'synced', reason: 'tidak perlu dikirim ulang');
      final izin = await baru.select(baru.permissions).get();
      expect(
        izin.firstWhere((p) => p.code == 'manage_categories').name,
        'Kelola Kategori',
      );
    },
  );

  group('simpanKategori', () {
    test('tambah, sembunyikan, dan hapus dalam satu simpan', () async {
      await kategori('k-kopi', 'Kopi');
      await kategori('k-snack', 'Snack');
      await kategori('k-teh', 'Teh');
      await produk('p-1', 'k-kopi');
      await produk('p-2', 'k-kopi');

      await db.simpanKategori(
        tambah: [(nama: 'Mocktails', ikon: Icons.local_bar_rounded.codePoint)],
        tampil: {'k-snack': false, 'k-teh': true},
        hapus: ['k-kopi'],
      );

      final kopi = await ambil('k-kopi');
      expect(kopi.deletedAt, isNotNull);
      expect(kopi.syncStatus, 'pending');
      final p = await db.select(db.products).get();
      expect(p.map((x) => x.categoryId), everyElement(isNull));
      expect(p.map((x) => x.syncStatus), everyElement('pending'));
      expect(p, hasLength(2), reason: 'produknya tidak ikut terhapus');

      final snack = await ambil('k-snack');
      expect((snack.tampilDiKasir, snack.syncStatus), (false, 'pending'));
      final teh = await ambil('k-teh');
      expect(
        teh.syncStatus,
        'synced',
        reason: 'tidak berubah = tidak perlu dikirim',
      );

      final daftar = await db.watchCategories().first;
      expect(daftar.map((c) => c.name), ['Mocktails', 'Snack', 'Teh']);
      expect(daftar.first.iconCodepoint, Icons.local_bar_rounded.codePoint);
    });

    test('ubah nama & ikon: kategori dikirim, produknya tidak', () async {
      await kategori('k-kopi', 'Kopi');
      await produk('p-1', 'k-kopi');
      await db.simpanKategori(
        ubah: {
          'k-kopi': (nama: 'Kopi Susu', ikon: Icons.coffee_rounded.codePoint),
        },
      );
      final k = await ambil('k-kopi');
      expect(
        (k.name, k.iconCodepoint, k.syncStatus),
        ('Kopi Susu', Icons.coffee_rounded.codePoint, 'pending'),
      );
      final p = await db.select(db.products).getSingle();
      expect((p.categoryId, p.syncStatus), ('k-kopi', 'synced'));
    });

    test('tukar nama dua kategori sah', () async {
      await kategori('k-a', 'Kopi');
      await kategori('k-b', 'Teh');
      await db.simpanKategori(
        ubah: {
          'k-a': (nama: 'Teh', ikon: null),
          'k-b': (nama: 'Kopi', ikon: null),
        },
      );
      expect((await ambil('k-a')).name, 'Teh');
      expect((await ambil('k-b')).name, 'Kopi');
    });

    test(
      'ubah ke nama kategori lain ditolak, tidak tersimpan sebagian',
      () async {
        await kategori('k-kopi', 'Kopi');
        await kategori('k-teh', 'Teh');
        await expectLater(
          db.simpanKategori(
            ubah: {'k-teh': (nama: 'KOPI', ikon: null)},
            tampil: {'k-kopi': false},
          ),
          throwsStateError,
        );
        expect((await ambil('k-teh')).name, 'Teh');
        expect((await ambil('k-kopi')).tampilDiKasir, isTrue);
      },
    );

    test('kembaran lama tidak menghalangi ubah kategori lain', () async {
      await kategori('k-m1', 'Makanan');
      await kategori('k-m2', 'Makanan');
      await kategori('k-kopi', 'Kopi');
      await db.simpanKategori(
        ubah: {'k-kopi': (nama: 'Kopi Susu', ikon: null)},
      );
      expect((await ambil('k-kopi')).name, 'Kopi Susu');
    });

    test('nama kembar (beda huruf besar-kecil) ditolak, TIDAK ada yang '
        'tersimpan sebagian', () async {
      await kategori('k-kopi', 'Kopi');
      await kategori('k-teh', 'Teh');
      await expectLater(
        db.simpanKategori(
          tambah: [(nama: 'kopi', ikon: null)],
          hapus: ['k-teh'],
        ),
        throwsA(isA<StateError>()),
      );
      expect((await ambil('k-teh')).deletedAt, isNull);
      expect(await db.watchCategories().first, hasLength(2));
    });

    test('urut nama tanpa membedakan huruf besar-kecil', () async {
      await kategori('a', 'Snack');
      await kategori('b', 'kopi');
      await kategori('c', 'Makanan');
      final daftar = await db.watchCategories().first;
      expect(daftar.map((c) => c.name), ['kopi', 'Makanan', 'Snack']);
    });

    test('izin: Kelola Kategori, bukan Kelola Produk', () async {
      await kategori('k-kopi', 'Kopi');
      await masuk('cashier', const ['manage_products']);
      expect(
        () => db.simpanKategori(tampil: {'k-kopi': false}),
        throwsA(isA<StateError>()),
      );
      await masuk('cashier', const ['manage_categories']);
      await db.simpanKategori(tampil: {'k-kopi': false});
      expect((await ambil('k-kopi')).tampilDiKasir, isFalse);
    });

    test('Kelola Kategori bukan izin bawaan kasir baru', () {
      expect(izinBawaanKasir, isNot(contains('manage_categories')));
    });
  });

  group('sinkron tampil_di_kasir', () {
    test(
      'ikut dikirim; server tanpa kolom TIDAK mereset nilai di HP',
      () async {
        final terkirim = <Map<String, dynamic>>[];
        var server = <Map<String, dynamic>>[];
        final mesin = SyncEngine(db)
          ..penarikUntukTest = ((tabel, kolom, sejak, setelah, batas) async =>
              tabel == 'categories' ? server : const <Map<String, dynamic>>[])
          ..pengirimUntukTest = (tabel, baris) async {
            if (tabel == 'categories') terkirim.addAll(baris);
          };

        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: const Value('k-1'),
                name: 'Kopi',
                tampilDiKasir: const Value(false),
                updatedAt: Value(DateTime(2026, 10, 1)),
              ),
            );
        await mesin.dorongSemua();
        expect(terkirim.single['tampil_di_kasir'], isFalse);

        final cap = DateTime.utc(2026, 10, 2).toIso8601String();
        server = [
          {
            'id': 'k-1',
            'name': 'Kopi Susu',
            'icon_codepoint': null,
            // Kolom tampil_di_kasir tidak ada: SQL server belum dijalankan.
            'created_at': cap,
            'updated_at': cap,
            'deleted_at': null,
            'server_urut': cap,
          },
        ];
        await mesin.tarikTabel('categories');
        final k = await ambil('k-1');
        expect(k.name, 'Kopi Susu', reason: 'baris server memang diterima');
        expect(k.tampilDiKasir, isFalse);

        final cap2 = DateTime.utc(2026, 10, 3).toIso8601String();
        server = [
          {
            ...server.single,
            'tampil_di_kasir': true,
            'updated_at': cap2,
            'server_urut': cap2,
          },
        ];
        await mesin.tarikTabel('categories');
        expect((await ambil('k-1')).tampilDiKasir, isTrue);
      },
    );
  });

  group('saring kategori di Kasir', () {
    Category k(String id, {bool tampil = true}) => Category(
      id: id,
      name: id,
      tampilDiKasir: tampil,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      syncStatus: 'synced',
    );
    Product p(String id, String? kat) => Product(
      id: id,
      name: id,
      price: 1,
      categoryId: kat,
      hasSpicyOption: false,
      hasSweetOption: false,
      hasIceOption: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      syncStatus: 'synced',
    );

    final semua = [k('kopi'), k('musiman', tampil: false)];
    final produk = [
      p('latte', 'kopi'),
      p('es-buah', 'musiman'),
      p('kerupuk', null),
      p('yatim', 'sudah-dihapus'),
    ];
    List<String> id(List<Product> x) => [for (final e in x) e.id];

    test('tombol kategori yang disembunyikan tidak tampil', () {
      expect(kategoriDiKasir(semua).map((c) => c.id), ['kopi']);
    });
    test('"Semua" tetap memuat produk kategori tersembunyi', () {
      expect(id(saringPerKategori(produk, semua, null)), contains('es-buah'));
    });
    test(
      'Tanpa Kategori = tanpa kategori atau kategorinya sudah tidak ada',
      () {
        expect(adaProdukTanpaKategori(produk, semua), isTrue);
        expect(id(saringPerKategori(produk, semua, pilihanTanpaKategori)), [
          'kerupuk',
          'yatim',
        ]);
        expect(
          adaProdukTanpaKategori([p('latte', 'kopi')], semua),
          isFalse,
          reason: 'tombolnya hanya muncul kalau ada produknya',
        );
      },
    );
    test('kategori terpilih yang baru disembunyikan dianggap Semua', () {
      expect(pilihanEfektif(semua, 'musiman'), isNull);
      expect(saringPerKategori(produk, semua, 'musiman'), hasLength(4));
      expect(id(saringPerKategori(produk, semua, 'kopi')), ['latte']);
    });
  });

  group('daftar ikon', () {
    test('26 pilihan, tidak ada yang kembar', () {
      expect(kIkonPilihanKategori, hasLength(26));
      expect(
        kIkonPilihanKategori.map((i) => i.codePoint).toSet(),
        hasLength(kIkonPilihanKategori.length),
      );
    });

    test('tiap pilihan tampil lagi sebagai ikon yang sama', () {
      for (final ikon in kIkonPilihanKategori) {
        expect(categoryIconFromCodepoint(ikon.codePoint), ikon);
      }
    });

    test('ikon lama yang tidak bisa dipilih lagi tetap dikenali', () {
      for (final ikon in [
        Icons.dinner_dining,
        Icons.tapas,
        Icons.sell_rounded,
      ]) {
        expect(categoryIconFromCodepoint(ikon.codePoint), ikon);
      }
    });
  });

  group('halaman', () {
    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> tunggu(WidgetTester t, [int ms = 80]) async {
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pumpAndSettle();
    }

    Future<void> buka(WidgetTester t) async {
      layarHp(t);
      await t.runAsync(() async {
        await kategori('k-kopi', 'Kopi');
        await kategori('k-snack', 'Snack', tampil: false);
        await produk('p-1', 'k-kopi');
        await produk('p-2', 'k-kopi');
        await produk('p-3', 'k-kopi');
        await produk('p-4', null);
      });
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                        builder: (_) =>
                            KategoriPage(repo: ProductRepository(db)),
                      ),
                    ),
                    child: const Text('buka'),
                  ),
                ),
              ),
            ),
          ),
        );
      });
      await t.tap(find.text('buka'));
      await tunggu(t);
    }

    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(Duration.zero);
    }

    testWidgets('daftar: jumlah produk, tersembunyi, dan Tanpa Kategori', (
      t,
    ) async {
      await buka(t);
      expect(find.text('3 produk'), findsOneWidget);
      expect(find.text('0 produk · disembunyikan di Kasir'), findsOneWidget);
      expect(find.text('Tanpa Kategori'), findsOneWidget);
      expect(find.text('1 produk'), findsOneWidget);
      expect(find.text('Bawaan'), findsOneWidget);
      expect(find.text('1 dari 2 tampil di Kasir'), findsOneWidget);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('tambah: nama kosong/kembar ditolak, yang baru masuk draf', (
      t,
    ) async {
      await buka(t);
      await t.tap(find.bySemanticsLabel('Tambah kategori'));
      await t.pump();
      expect(find.text('Nama kategori wajib diisi'), findsOneWidget);

      for (final kembar in ['kopi', 'tanpa kategori']) {
        await t.enterText(find.byType(TextField), kembar);
        await t.tap(find.bySemanticsLabel('Tambah kategori'));
        await t.pump();
        expect(find.text('Kategori sudah ada'), findsOneWidget, reason: kembar);
      }

      await t.enterText(find.byType(TextField), '  Mocktails  ');
      await t.tap(find.bySemanticsLabel('Tambah kategori'));
      await t.pump();
      expect(find.text('Mocktails'), findsOneWidget);
      expect(find.text('Baru'), findsOneWidget);
      expect(find.text('Simpan Perubahan'), findsOneWidget);
      final diDb = await t.runAsync(() => db.watchCategories().first);
      expect(diDb, hasLength(2), reason: 'belum disimpan');
      await lepas(t);
    });

    testWidgets('pilihan ikon: sendok garpu & cookie bisa dipilih', (t) async {
      await buka(t);
      expect(find.byIcon(Icons.cookie), findsOneWidget);
      await t.tap(find.byIcon(Icons.restaurant_rounded));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Lauk');
      await t.tap(find.bySemanticsLabel('Tambah kategori'));
      await t.pump();
      await t.tap(find.text('Simpan Perubahan'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      final diDb = await t.runAsync(() => db.watchCategories().first);
      expect(
        diDb!.firstWhere((k) => k.name == 'Lauk').iconCodepoint,
        Icons.restaurant_rounded.codePoint,
      );
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    testWidgets('pilihan ikon: Add on memakai ikon plus sendiri', (t) async {
      await buka(t);
      await t.ensureVisible(find.byIcon(Icons.add_circle_rounded));
      await t.tap(find.byIcon(Icons.add_circle_rounded));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Add on');
      await t.tap(find.bySemanticsLabel('Tambah kategori'));
      await t.pump();
      await t.tap(find.text('Simpan Perubahan'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      final diDb = await t.runAsync(() => db.watchCategories().first);
      expect(
        diDb!.firstWhere((k) => k.name == 'Add on').iconCodepoint,
        Icons.add_circle_rounded.codePoint,
      );
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    Future<void> bukaEdit(WidgetTester t, String nama) async {
      await t.tap(find.byTooltip('Edit $nama'));
      await t.pumpAndSettle();
      expect(find.text('Edit Kategori'), findsOneWidget);
    }

    Future<void> simpanEdit(WidgetTester t) async {
      await t.tap(find.text('Simpan'));
      await t.pumpAndSettle();
    }

    testWidgets('edit nama & ikon: masuk draf "Diubah", berlaku saat Simpan', (
      t,
    ) async {
      await buka(t);
      await bukaEdit(t, 'Kopi');
      expect(
        t.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Kopi',
      );
      await t.tap(find.byIcon(Icons.coffee_rounded).last);
      await t.enterText(find.byType(TextField).last, '  Kopi   Susu ');
      await simpanEdit(t);
      expect(find.text('Edit Kategori'), findsNothing);
      expect(find.text('Kopi Susu'), findsOneWidget);
      expect(find.text('Diubah'), findsOneWidget);
      expect(find.text('Simpan Perubahan'), findsOneWidget);
      expect((await t.runAsync(() => ambil('k-kopi')))!.name, 'Kopi');

      await t.tap(find.text('Simpan Perubahan'));
      await tunggu(t);
      final k = (await t.runAsync(() => ambil('k-kopi')))!;
      expect(
        (k.name, k.iconCodepoint),
        ('Kopi Susu', Icons.coffee_rounded.codePoint),
      );
      expect(find.text('Diubah'), findsNothing);
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    testWidgets('edit: nama kosong/kembar ditolak, lembar tetap terbuka', (
      t,
    ) async {
      await buka(t);
      await bukaEdit(t, 'Kopi');
      for (final (nama, galat) in [
        ('', 'Nama kategori wajib diisi'),
        ('snack', 'Kategori sudah ada'),
        ('tanpa kategori', 'Kategori sudah ada'),
      ]) {
        await t.enterText(find.byType(TextField).last, nama);
        await simpanEdit(t);
        expect(find.text(galat), findsOneWidget, reason: nama);
        expect(find.text('Edit Kategori'), findsOneWidget);
      }
      // Nama sendiri boleh (mis. hanya ganti ikon).
      await t.enterText(find.byType(TextField).last, 'KOPI');
      await simpanEdit(t);
      expect(find.text('Edit Kategori'), findsNothing, reason: 'tertutup');
      expect(find.text('Diubah'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('edit lalu Batal: tidak ada perubahan', (t) async {
      await buka(t);
      await bukaEdit(t, 'Kopi');
      await t.enterText(find.byType(TextField).last, 'Teh');
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(find.text('Kopi'), findsOneWidget);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('kembali ke nama & ikon asal: lencana "Diubah" hilang', (
      t,
    ) async {
      await buka(t);
      await bukaEdit(t, 'Kopi');
      await t.enterText(find.byType(TextField).last, 'Teh');
      await simpanEdit(t);
      await bukaEdit(t, 'Teh');
      await t.enterText(find.byType(TextField).last, 'Kopi');
      await simpanEdit(t);
      expect(find.text('Diubah'), findsNothing);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('Tanpa Kategori tidak bisa diedit', (t) async {
      await buka(t);
      expect(find.byTooltip('Edit Tanpa Kategori'), findsNothing);
      expect(find.byTooltip('Edit Kopi'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('kategori baru yang belum disimpan bisa diedit', (t) async {
      await buka(t);
      await t.enterText(find.byType(TextField), 'Mocktails');
      await t.tap(find.bySemanticsLabel('Tambah kategori'));
      await t.pump();
      await bukaEdit(t, 'Mocktails');
      await t.enterText(find.byType(TextField).last, 'Mojito');
      await simpanEdit(t);
      expect(find.text('Mojito'), findsOneWidget);
      expect(find.text('Baru'), findsOneWidget);
      expect(find.text('Diubah'), findsNothing);
      await t.tap(find.text('Simpan Perubahan'));
      await tunggu(t);
      final semua = await t.runAsync(() => db.watchCategories().first);
      expect(semua!.map((k) => k.name), contains('Mojito'));
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    testWidgets('nama dibatasi 20 huruf', (t) async {
      await buka(t);
      await t.enterText(find.byType(TextField), 'A' * 25);
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'A' * panjangNamaKategori,
      );
      await lepas(t);
    });

    testWidgets('hapus: ditanya, masuk draf, baru berlaku saat Simpan', (
      t,
    ) async {
      await buka(t);
      await t.tap(find.byTooltip('Hapus Kopi'));
      await t.pumpAndSettle();
      expect(find.text('Hapus kategori Kopi?'), findsOneWidget);
      expect(
        find.text('3 produk di kategori ini akan pindah ke Tanpa Kategori.'),
        findsOneWidget,
      );
      await t.tap(find.text('Hapus'));
      await t.pumpAndSettle();
      expect(find.text('Kopi'), findsNothing);
      expect(find.text('4 produk'), findsOneWidget, reason: 'Tanpa Kategori');
      expect(
        (await t.runAsync(() => ambil('k-kopi')))!.deletedAt,
        isNull,
        reason: 'belum disimpan',
      );

      await t.tap(find.text('Simpan Perubahan'));
      await tunggu(t, 200);
      expect((await t.runAsync(() => ambil('k-kopi')))!.deletedAt, isNotNull);
      final p = await t.runAsync(() => db.select(db.products).get());
      expect(p!.map((x) => x.categoryId), everyElement(isNull));
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await lepas(t);
    });

    testWidgets('kategori tanpa produk: teks hapus berbeda', (t) async {
      await buka(t);
      await t.tap(find.byTooltip('Hapus Snack'));
      await t.pumpAndSettle();
      expect(
        find.text('Kategori ini akan dihapus dari daftar.'),
        findsOneWidget,
      );
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(find.text('Snack'), findsOneWidget);
      expect(find.text('Tidak ada perubahan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets(
      'mata: sembunyi/tampil, kembali ke awal = tidak ada perubahan',
      (t) async {
        await buka(t);
        await t.tap(find.byTooltip('Sembunyikan di Kasir'));
        await t.pump();
        expect(find.text('3 produk · disembunyikan di Kasir'), findsOneWidget);
        expect(find.text('0 dari 2 tampil di Kasir'), findsOneWidget);
        expect(find.text('Simpan Perubahan'), findsOneWidget);
        await t.tap(find.byTooltip('Tampilkan di Kasir').first);
        await t.pump();
        expect(find.text('Tidak ada perubahan'), findsOneWidget);
        await lepas(t);
      },
    );

    testWidgets('kembali dengan perubahan → "Buang perubahan?"', (t) async {
      await buka(t);
      await t.tap(find.byTooltip('Sembunyikan di Kasir'));
      await t.pump();
      await t.tap(find.byTooltip('Kembali'));
      await t.pumpAndSettle();
      expect(find.text('Buang perubahan?'), findsOneWidget);
      expect(
        find.text('Perubahan kategori yang belum disimpan akan hilang.'),
        findsOneWidget,
      );
      await t.tap(find.text('Lanjut edit'));
      await t.pumpAndSettle();
      expect(find.byType(KategoriPage), findsOneWidget);

      await t.tap(find.byTooltip('Kembali'));
      await t.pumpAndSettle();
      await t.tap(find.text('Buang'));
      await t.pumpAndSettle();
      expect(find.byType(KategoriPage), findsNothing);
      expect(
        (await t.runAsync(() => ambil('k-kopi')))!.tampilDiKasir,
        isTrue,
        reason: 'dibuang, tidak tersimpan',
      );
      await lepas(t);
    });

    testWidgets('kembali tanpa perubahan langsung keluar', (t) async {
      await buka(t);
      await t.tap(find.byTooltip('Kembali'));
      await t.pumpAndSettle();
      expect(find.byType(KategoriPage), findsNothing);
      await lepas(t);
    });
  });
}
