import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/app/jaring_pengaman.dart';
import 'package:kasir_app/data/pemulihan/pemulihan_data.dart';
import 'package:kasir_app/data/pemulihan/penjaga_database.dart';
import 'package:kasir_app/shared/services/catatan_error.dart';
import 'package:kasir_app/utils/pesan_galat.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Audit 6 Nov nomor 62: error tak terduga dicatat di HP dan dikirim ke
/// server; database yang rusak di tengah pemakaian menampilkan layar Data
/// Rusak dari halaman mana pun.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  late CatatanError c;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folder = Directory.systemTemp.createTempSync('uji_catatan');
    c = CatatanError.untukTest();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  File berkas() => File('${folder.path}/catatan_error.json');
  final jejak = StackTrace.fromString('#0 a\n#1 b\n#2 c\n#3 d');

  group('mencatat', () {
    test('isi catatan; error yang sama digabung jadi hitungan', () async {
      await c.siapkan(folder.path);
      for (var i = 0; i < 37; i++) {
        c.catat(StateError('layar gagal'), jejak, sumber: 'tampilan');
      }
      c.catat(StateError('lain'), jejak, sumber: 'latar');
      expect(c.isi, hasLength(2));
      final b = c.isi.first;
      expect(b['jumlah'], 37);
      expect(b['pesan'], 'Bad state: layar gagal');
      expect(b['sumber'], 'tampilan');
      expect(b['versi'], isNotEmpty);
      expect(b['jejak'], contains('#0 a'));
      expect(DateTime.parse(b['waktu'] as String).isUtc, isTrue);
    });

    test('objek error yang sama tidak dihitung dua kali', () async {
      final e = StateError('sekali');
      c.catat(e, jejak, sumber: 'tertangkap');
      c.catat(e, jejak, sumber: 'tertangkap');
      expect(c.isi.single['jumlah'], 1);
    });

    test('tidak ada internet tidak dicatat', () {
      c.catat(const SocketException('putus'), jejak, sumber: 'latar');
      expect(c.isi, isEmpty);
    });

    test('paling banyak 200; pesan dan jejak dipotong', () {
      for (var i = 0; i < 230; i++) {
        c.catat(
          'galat $i ${'x' * 900}',
          StackTrace.fromString('#0\n' * 80),
          sumber: 'latar',
        );
      }
      expect(c.isi, hasLength(CatatanError.batasSimpan));
      expect(c.isi.first['pesan'], startsWith('galat 30 '));
      expect((c.isi.first['pesan'] as String).length, lessThan(520));
      expect(
        '\n'.allMatches(c.isi.first['jejak'] as String).length,
        lessThan(21),
      );
    });

    test(
      'tersimpan ke berkas dan dimuat lagi; berkas rusak = mulai kosong',
      () async {
        await c.siapkan(folder.path);
        c.catat(StateError('a'), jejak, sumber: 'latar');
        await c.simpan();
        final baru = CatatanError.untukTest();
        await baru.siapkan(folder.path);
        expect(baru.isi.single['pesan'], 'Bad state: a');

        berkas().writeAsStringSync('{rusak');
        final lagi = CatatanError.untukTest();
        await lagi.siapkan(folder.path);
        expect(lagi.isi, isEmpty);
        lagi.catat(StateError('b'), jejak, sumber: 'latar');
        await lagi.simpan();
        expect(jsonDecode(berkas().readAsStringSync()), hasLength(1));
      },
    );

    test(
      'pesanGalat mencatat galat yang tidak dikenali, bukan yang dikenali',
      () {
        final sebelum = CatatanError.instance.isi.length;
        pesanGalat(StateError('Nama sudah dipakai'));
        pesanGalat(const SocketException('putus'));
        expect(CatatanError.instance.isi.length, sebelum);
        pesanGalat(Exception('aneh ${DateTime.now().microsecondsSinceEpoch}'));
        expect(CatatanError.instance.isi.length, sebelum + 1);
        expect(CatatanError.instance.isi.last['sumber'], 'tertangkap');
      },
    );
  });

  group('mengirim', () {
    test('yang sampai dihapus; paling banyak 50 per kiriman; kolom dalam '
        'tidak ikut', () async {
      await c.siapkan(folder.path);
      for (var i = 0; i < 60; i++) {
        c.catat('galat $i', jejak, sumber: 'latar');
      }
      final kiriman = <List<Map<String, dynamic>>>[];
      c.pengirimUntukTest = (b) async => kiriman.add(b);
      await c.kirim();
      expect(kiriman.single, hasLength(50));
      expect(kiriman.single.first.keys.toSet(), {
        'id',
        'waktu',
        'akun',
        'peran',
        'versi',
        'sumber',
        'pesan',
        'jejak',
        'jumlah',
      });
      expect(c.isi, hasLength(10));
      expect(jsonDecode(berkas().readAsStringSync()), hasLength(10));
      await c.kirim();
      expect(c.isi, isEmpty);
    });

    test('gagal kirim atau fungsi belum ada di server: tetap menunggu, '
        'tanpa galat', () async {
      c.catat('galat', jejak, sumber: 'latar');
      c.pengirimUntukTest = (_) async =>
          throw PostgrestException(message: 'x', code: 'PGRST202');
      await c.kirim();
      c.pengirimUntukTest = (_) async => throw const SocketException('putus');
      await c.kirim();
      expect(c.isi, hasLength(1));
    });

    test('terulang selagi dikirim: sisanya jadi catatan baru', () async {
      c.catat('galat', jejak, sumber: 'latar');
      final idAwal = c.isi.single['id'];
      c.pengirimUntukTest = (_) async {
        c.catat('galat', jejak, sumber: 'latar');
        c.catat('galat', jejak, sumber: 'latar');
      };
      await c.kirim();
      expect(c.isi.single['jumlah'], 2);
      expect(c.isi.single['id'], isNot(idAwal));
    });
  });

  group('database rusak di tengah pemakaian', () {
    final rusak = SqliteException(
      extendedResultCode: 11,
      message: 'database disk image is malformed',
    );

    test('galat database memicu pemeriksaan; terbukti rusak = menyala dan '
        'pemeriksaan penuh dijadwalkan untuk buka berikutnya', () async {
      SharedPreferences.setMockInitialValues({PemulihanData.kunciCekPenuh: 1});
      var diperiksa = 0;
      final p = PenjagaDatabase.untukTest()
        ..pemeriksaUntukTest = () async {
          diperiksa++;
          return KeadaanDatabase.rusak;
        };
      p.laporkan(StateError('bukan database'));
      await pumpEventQueue();
      expect((diperiksa, p.rusak.value), (0, false));

      p.laporkan(rusak);
      await pumpEventQueue();
      expect((diperiksa, p.rusak.value), (1, true));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PemulihanData.kunciCekPenuh), isNull);
    });

    test('berkasnya ternyata sehat: tidak menyala, dan tidak diperiksa '
        'beruntun', () async {
      var diperiksa = 0;
      final p = PenjagaDatabase.untukTest()
        ..pemeriksaUntukTest = () async {
          diperiksa++;
          return KeadaanDatabase.sehat;
        };
      p.laporkan(rusak);
      await pumpEventQueue();
      p.laporkan(rusak);
      await pumpEventQueue();
      expect((diperiksa, p.rusak.value), (1, false));
    });

    testWidgets('layar Data Rusak menggantikan halaman yang terbuka; '
        'tombolnya menutup aplikasi', (t) async {
      final p = PenjagaDatabase.untukTest();
      var ditutup = 0;
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) => PenutupDataRusak(
            penjaga: p,
            onTutup: () async => ditutup++,
            child: child!,
          ),
          home: const Scaffold(body: Text('Halaman Kasir')),
        ),
      );
      expect(find.text('Halaman Kasir'), findsOneWidget);

      p.rusak.value = true;
      await t.pumpAndSettle();
      expect(find.text('Halaman Kasir'), findsNothing);
      expect(find.text('Data di HP ini rusak'), findsOneWidget);
      expect(
        find.textContaining('Tutup aplikasi ini, lalu buka lagi'),
        findsOneWidget,
      );
      expect(find.text('Perbaiki data'), findsNothing);
      await t.tap(find.text('Tutup aplikasi'));
      await t.pump();
      expect(ditutup, 1);
    });
  });

  testWidgets('pengganti bagian yang gagal tampil tidak butuh tema', (t) async {
    await t.pumpWidget(const BagianGagalTampil());
    expect(find.textContaining('gagal ditampilkan'), findsOneWidget);
  });
}
