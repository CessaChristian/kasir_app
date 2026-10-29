import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA kedua S11 — internet putus di tengah kirim, dan tombol Batalkan.
///
/// Dulu potongan yang gagal karena APA PUN dipecah dan dicoba satu per satu.
/// Dengan sinyal ada tapi internet mati, tiap baris menunggu 15 detik — satu
/// potongan 100 baris ±25 menit, dan tarik layar ikut menunggu. Pemecahan
/// itu hanya berguna untuk baris yang DITOLAK server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> produk(int n) async {
    for (var i = 0; i < n; i++) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value('p-$i'),
            name: 'Produk $i',
            price: 1000,
            syncStatus: const Value('pending'),
          ));
    }
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: const Value('k-1'),
          name: 'Minuman',
          syncStatus: const Value('pending'),
        ));
  }

  Future<int> masihTertunda() async => (await (db.select(db.products)
            ..where((p) => p.syncStatus.equals('pending')))
          .get())
      .length;

  for (final (nama, galat) in <(String, Object Function())>[
    ('waktu habis', () => TimeoutException('15 detik')),
    ('soket putus', () => const SocketException('Network is unreachable')),
  ]) {
    test('$nama: putaran berhenti, TIDAK dicoba satu per satu', () async {
      await produk(5);
      final kiriman = <String>[];
      final mesin = SyncEngine(db)
        ..pengirimUntukTest = (tabel, baris) async {
          kiriman.add('$tabel×${baris.length}');
          throw galat();
        };
      final (terkirim, gagal) = await mesin.dorongSemua();
      expect(kiriman, ['categories×1'],
          reason: 'satu permintaan, lalu berhenti — tabel lain tidak dicoba');
      expect(terkirim, 0);
      expect(gagal, hasLength(1));
      expect(await masihTertunda(), 5, reason: 'tetap aman di HP');
    });
  }

  test('ditolak server lalu putus di tengah satu-per-satu: berhenti', () async {
    await produk(5);
    var ke = 0;
    final mesin = SyncEngine(db)
      ..pengirimUntukTest = (tabel, baris) async {
        if (tabel != 'products') return;
        ke++;
        if (ke == 1) throw Exception('invalid input syntax'); // ditolak
        if (ke == 2) return; // baris pertama lolos
        throw TimeoutException('15 detik');
      };
    await mesin.dorongSemua();
    expect(ke, 3, reason: 'baris ketiga putus — sisanya tidak ditunggu');
    expect(await masihTertunda(), 4);
  });

  test('Batalkan: potongan berikutnya tidak dikirim, yang sudah sampai '
      'tetap tercatat terkirim', () async {
    await produk(150); // dua potongan
    final mesin = SyncEngine(db);
    var potongan = 0;
    mesin.pengirimUntukTest = (tabel, baris) async {
      if (tabel != 'products') return;
      potongan++;
      mesin.batalkan(); // ditekan selagi potongan pertama dikirim
    };
    final (terkirim, gagal) = await mesin.dorongSemua();
    expect(potongan, 1);
    expect(terkirim, 101, reason: 'kategori + 100 produk sudah di server');
    expect(gagal.single, contains('dibatalkan'));
    expect(await masihTertunda(), 50);
  });
}
