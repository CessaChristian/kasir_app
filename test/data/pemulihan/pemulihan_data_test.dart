import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Column, Table;
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/pemulihan/pemulihan_data.dart';
import 'package:kasir_app/features/pemulihan/layar_data_rusak.dart';
import 'package:kasir_app/utils/pesan_galat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory folder;
  late PemulihanData pemulihan;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('pemulihan');
    pemulihan = PemulihanData(folder.path);
  });
  tearDown(() => folder.deleteSync(recursive: true));

  AppDatabase buka() => AppDatabase.forTesting(
        NativeDatabase(
          pemulihan.berkasDatabase,
          setup: (d) => d.execute('PRAGMA foreign_keys = ON'),
        ),
      );

  Future<void> kategori(AppDatabase db, String id, String nama,
      {String status = 'pending', int waktu = 1000}) {
    return db.customStatement(
      'INSERT INTO categories (id, name, updated_at, sync_status) '
      'VALUES (?, ?, ?, ?)',
      [id, nama, waktu, status],
    );
  }

  Future<void> produk(AppDatabase db, String id, String nama, String kat) {
    return db.customStatement(
      "INSERT INTO products (id, name, price, category_id, sync_status) "
      "VALUES (?, ?, 1000, ?, 'pending')",
      [id, nama, kat],
    );
  }

  Future<void> buatDatabaseSehat() async {
    final db = buka();
    await kategori(db, 'k1', 'Minuman');
    await db.close();
  }

  group('pemeriksaan berkas', () {
    KeadaanDatabase periksa() =>
        periksaBerkasDatabase(pemulihan.berkasDatabase.path);

    test('belum ada berkas berarti pemasangan baru', () {
      expect(periksa(), KeadaanDatabase.kosong);
    });

    test('database normal lolos', () async {
      await buatDatabaseSehat();
      expect(periksa(), KeadaanDatabase.sehat);
    });

    test('awal berkas tertimpa terdeteksi', () async {
      await buatDatabaseSehat();
      final b = pemulihan.berkasDatabase.openSync(mode: FileMode.append);
      b.setPositionSync(0);
      b.writeFromSync(List.filled(100, 7));
      b.closeSync();
      expect(periksa(), KeadaanDatabase.rusak);
    });

    test('halaman data rusak terdeteksi walau daftar tabelnya masih utuh',
        () async {
      final db = buka();
      await db.transaction(() async {
        for (var i = 0; i < 3000; i++) {
          await kategori(db, 'k$i', 'Kategori nomor $i');
        }
      });
      await db.close();
      final b = pemulihan.berkasDatabase.openSync(mode: FileMode.append);
      b.setPositionSync(b.lengthSync() - 4096 * 8);
      b.writeFromSync(List.filled(4096 * 8, 7));
      b.closeSync();
      // Tanpa integrity_check berkas ini lolos: kerusakannya baru ketahuan
      // saat barisnya dibaca, jadi layar login tetap muncul seperti biasa.
      final d = buka();
      await d.customSelect('SELECT COUNT(*) FROM users').get();
      await d.close();
      expect(periksa(), KeadaanDatabase.rusak);
    });

    test('tabel inti hilang terdeteksi', () async {
      final db = buka();
      await db.customStatement('DROP TABLE expenses');
      await db.close();
      expect(periksa(), KeadaanDatabase.rusak);
    });

    test('database lenyap tapi ada salinan: rusak, bukan pasang baru',
        () async {
      pemulihan.berkasCadangan.writeAsStringSync(jsonEncode({
        'categories': [
          {'id': 'k1'}
        ],
      }));
      expect(await pemulihan.periksa(), KeadaanDatabase.rusak);
    });
  });

  group('buku cadangan', () {
    test('tulisan baru tersalin sendiri, yang terkirim tidak ikut', () async {
      final db = buka();
      await kategori(db, 'lama', 'Terkirim', status: 'synced');
      final buku = BukuCadangan(db, pemulihan.berkasCadangan,
          jeda: const Duration(milliseconds: 10));
      buku.ikuti();
      await db.into(db.categories).insert(
          CategoriesCompanion.insert(id: const Value('baru'), name: 'Baru'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await buku.berhenti();
      final isi = jsonDecode(pemulihan.berkasCadangan.readAsStringSync());
      expect([for (final b in isi['categories']) b['id']], ['baru']);
      await db.close();
    });

    test('gagal membaca database: salinan lama tidak tertimpa', () async {
      final db = buka();
      await kategori(db, 'k1', 'Minuman');
      final buku = BukuCadangan(db, pemulihan.berkasCadangan);
      await buku.simpan();
      final sebelum = pemulihan.berkasCadangan.readAsStringSync();
      await db.customStatement('DROP TABLE categories');
      await buku.simpan();
      expect(pemulihan.berkasCadangan.readAsStringSync(), sebelum);
      await db.close();
    });
  });

  group('pemulihan', () {
    Future<void> salin(AppDatabase db) =>
        BukuCadangan(db, pemulihan.berkasCadangan).simpan();

    test('alur lengkap: rusak, karantina, tarik, masukkan, tetap pending',
        () async {
      var db = buka();
      await kategori(db, 'k1', 'Minuman');
      await produk(db, 'p1', 'Es Teh', 'k1');
      await salin(db);
      await db.close();

      await pemulihan.karantina();
      expect(await pemulihan.menunggu(), isTrue);
      expect(pemulihan.berkasDatabase.existsSync(), isFalse);
      expect(pemulihan.berkasRusak.existsSync(), isTrue,
          reason: 'berkas rusak disimpan, bukan dihapus');

      db = buka();
      final hasil = await pemulihan.masukkan(db);
      expect(hasil.masuk, 2);
      expect(hasil.gagal, 0);
      final p = await db
          .customSelect("SELECT sync_status FROM products WHERE id = 'p1'")
          .getSingle();
      expect(p.read<String>('sync_status'), 'pending',
          reason: 'harus tetap pending supaya terkirim ke server');
      await db.close();
    });

    test('diulang dua kali tidak dobel', () async {
      final db = buka();
      await kategori(db, 'k1', 'Minuman');
      await salin(db);
      await db.customStatement('DELETE FROM categories');
      await pemulihan.masukkan(db);
      final kedua = await pemulihan.masukkan(db);
      expect(kedua.masuk, 0);
      expect(kedua.gagal, 0);
      final n = await db.customSelect('SELECT COUNT(*) n FROM categories').getSingle();
      expect(n.read<int>('n'), 1);
      await db.close();
    });

    test('versi server sama atau lebih baru tidak ditimpa', () async {
      final db = buka();
      await kategori(db, 'k1', 'Versi HP', waktu: 1000);
      await salin(db);
      await db.customStatement(
        "UPDATE categories SET name = 'Versi server', updated_at = 2000, "
        "sync_status = 'synced' WHERE id = 'k1'",
      );
      await pemulihan.masukkan(db);
      final k = await db.customSelect('SELECT name FROM categories').getSingle();
      expect(k.read<String>('name'), 'Versi server');
      await db.close();
    });

    test('salinan lebih baru menang, dan anak barisnya tidak ikut terhapus',
        () async {
      final db = buka();
      await db.customStatement(
        "INSERT INTO users (id, username, pin_hash, salt, role, updated_at, "
        "sync_status) VALUES ('u1', 'edit offline', 'h', 's', 'cashier', 3000, "
        "'pending')",
      );
      final izin = await db
          .customSelect('SELECT code FROM permissions LIMIT 1')
          .getSingle();
      await db.customStatement(
        "INSERT INTO user_permissions (id, user_id, permission_code, "
        "sync_status) VALUES ('i1', 'u1', ?, 'synced')",
        [izin.read<String>('code')],
      );
      await salin(db);
      await db.customStatement(
        "UPDATE users SET username = 'lama', updated_at = 1000, "
        "sync_status = 'synced' WHERE id = 'u1'",
      );
      await pemulihan.masukkan(db);
      final u = await db.customSelect('SELECT username FROM users').getSingle();
      expect(u.read<String>('username'), 'edit offline');
      // user_permissions memakai ON DELETE CASCADE ke users.
      final n = await db
          .customSelect('SELECT COUNT(*) n FROM user_permissions')
          .getSingle();
      expect(n.read<int>('n'), 1);
      await db.close();
    });

    test('baris yang ditolak tidak menggagalkan yang lain dan disimpan',
        () async {
      final db = buka();
      await kategori(db, 'k1', 'Minuman');
      await kategori(db, 'k2', 'Makanan');
      await produk(db, 'p1', 'Es Teh', 'k1');
      await salin(db);
      await db.customStatement('DELETE FROM products');
      await db.customStatement('DELETE FROM categories');
      // Induk p1 tidak ikut tersalin: foreign key menolak p1, k2 tetap masuk.
      final isi = jsonDecode(pemulihan.berkasCadangan.readAsStringSync());
      isi['categories'].removeWhere((b) => b['id'] == 'k1');
      pemulihan.berkasCadangan.writeAsStringSync(jsonEncode(isi));
      final hasil = await pemulihan.masukkan(db);
      expect(hasil.masuk, 1);
      expect(hasil.gagal, 1);
      final sisa = jsonDecode(pemulihan.berkasSisa.readAsStringSync());
      expect(sisa['products'][0]['id'], 'p1');
      await db.close();
    });
  });

  group('kabar sesudah diperbaiki', () {
    Future<void> beritahu(WidgetTester tester, HasilPemulihan hasil) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => beritahuHasilPemulihan(context, hasil),
            child: const Text('kabari'),
          ),
        ),
      ));
      await tester.tap(find.text('kabari'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('semua kembali: toast berhasil', (tester) async {
      await beritahu(tester, const HasilPemulihan(masuk: 4, gagal: 0));
      expect(find.text('Perbaikan data berhasil'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('sebagian gagal: dialog, bukan toast berhasil', (tester) async {
      await beritahu(tester, const HasilPemulihan(masuk: 3, gagal: 1));
      expect(find.text('Perbaikan data berhasil'), findsNothing);
      expect(find.textContaining('1 data belum terkirim'), findsOneWidget);
    });
  });

  group('kalimat ke kasir', () {
    test('menyebut jumlah transaksi, data lain, atau salinan hilang', () {
      expect(
        LayarDataRusak.kalimatCadangan(
            const RingkasanCadangan(transaksi: 12, semua: 30)),
        '12 transaksi yang belum terkirim masih aman.',
      );
      expect(
        LayarDataRusak.kalimatCadangan(
            const RingkasanCadangan(transaksi: 0, semua: 3)),
        '3 data yang belum terkirim masih aman.',
      );
      expect(
        LayarDataRusak.kalimatCadangan(
            const RingkasanCadangan(transaksi: 0, semua: 0)),
        'Semua data sudah terkirim ke server.',
      );
      expect(LayarDataRusak.kalimatCadangan(null), contains('cocokkan'));
    });

    test('pesan galat menuntun ke layar perbaikan, bukan install ulang', () {
      expect(pesanDatabaseRusak, contains('Tutup lalu buka lagi'));
      expect(pesanDatabaseRusak, isNot(contains('install ulang')));
    });
  });
}
