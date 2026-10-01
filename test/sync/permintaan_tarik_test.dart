import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Memeriksa PERMINTAAN yang benar-benar dikirim ke Supabase saat menarik.
///
/// Test lain memakai server palsu yang mengurutkan sendiri — jadi kalau
/// engine meminta urutan yang salah, server palsunya diam-diam
/// membetulkannya dan test tetap hijau. Itu persis yang terjadi: bawaan
/// `order()` di pustaka postgrest adalah TURUN, engine tidak menulis
/// `ascending: true`, dan HP yang dipasang dari nol cuma mendapat 500 item
/// struk terbaru dari 633.
///
/// Di sini klien Supabase sungguhan diarahkan ke server HTTP lokal, dan URL
/// yang sampai ke server itulah yang diperiksa.
///
/// SENGAJA tanpa `TestWidgetsFlutterBinding`: binding itu membelokkan semua
/// permintaan HTTP menjadi galat 400.
void main() {
  late HttpServer http;
  late List<Uri> permintaan;
  late List<List<Map<String, dynamic>>> jawaban;
  late AppDatabase db;
  late SyncEngine mesin;

  Map<String, dynamic> kategori(int i) {
    const cap = '2026-09-04T13:54:59+00:00';
    return {
      'id': 'k-${i.toString().padLeft(4, '0')}',
      'name': 'Kategori $i',
      'icon_codepoint': null,
      'created_at': cap,
      'updated_at': cap,
      'deleted_at': null,
      'server_urut': cap,
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    permintaan = [];
    jawaban = [];
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      permintaan.add(req.uri);
      final isi = jawaban.isEmpty ? <Map<String, dynamic>>[] : jawaban.removeAt(0);
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(isi));
      await req.response.close();
    });

    db = AppDatabase.forTesting(NativeDatabase.memory());
    mesin = SyncEngine(db)
      ..klienUntukTest = SupabaseClient(
        'http://${http.address.host}:${http.port}',
        'kunci-palsu',
      );
  });

  tearDown(() async {
    await http.close(force: true);
    await db.close();
  });

  test('halaman diurutkan NAIK menurut kedatangan, lalu id', () async {
    jawaban.add([]);
    await mesin.tarikTabel('categories');

    expect(permintaan, hasLength(1));
    expect(
      permintaan.single.queryParameters['order'],
      'server_urut.asc.nullslast,id.asc.nullslast',
      reason: 'urutan TURUN membuat tarikan lebih dari satu halaman cuma '
          'mendapat baris terbaru — sisanya tidak pernah sampai',
    );
  });

  test('halaman kedua mulai SESUDAH pasangan (cap, id) baris terakhir',
      () async {
    jawaban.add([
      for (var i = 0; i < SyncEngine.ukuranHalaman; i++) kategori(i),
    ]);
    jawaban.add([]);

    await mesin.tarikTabel('categories');

    expect(permintaan, hasLength(2));
    final kedua = permintaan[1].queryParameters;
    final terakhir = 'k-${(SyncEngine.ukuranHalaman - 1).toString().padLeft(4, '0')}';
    expect(
      kedua['or'],
      '(server_urut.gt."2026-09-04T13:54:59.000Z",'
      'and(server_urut.eq."2026-09-04T13:54:59.000Z",id.gt."$terakhir"))',
      reason: 'dengan cap saja, gumpalan bercap sama yang lebih besar dari '
          'satu halaman membuat tarikan macet di halaman yang sama',
    );
    expect(kedua.containsKey('server_urut'), isFalse,
        reason: 'halaman kedua tidak boleh mulai lagi dari `gte` cap yang sama');
    expect(await db.select(db.categories).get(),
        hasLength(SyncEngine.ukuranHalaman));
  });
}
