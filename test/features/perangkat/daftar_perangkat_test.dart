import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/perangkat/pages/daftar_perangkat_page.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Daftar Perangkat (desain): kartu per HP, kelompok DICABUT, peringatan
/// "Tidak sinkron N hari", konfirmasi Cabut/Lupakan, Pulihkan tanpa tanya.
class _RepoPalsu extends PerangkatRepository {
  _RepoPalsu(this.daftar) : super.untukTest();

  List<Perangkat> daftar;
  final panggilan = <String>[];

  @override
  String? get idSaya => 'hp-owner';

  @override
  Future<List<Perangkat>> semua() async => daftar;

  Perangkat _ganti(String id, Perangkat Function(Perangkat) ubah) {
    final i = daftar.indexWhere((p) => p.id == id);
    return daftar[i] = ubah(daftar[i]);
  }

  @override
  Future<void> ubahNama(String id, String nama) async {
    panggilan.add('nama $id $nama');
    _ganti(id, (p) => _salin(p, nama: nama));
  }

  @override
  Future<void> ubahStatus(String id, {required bool aktif}) async {
    panggilan.add('status $id $aktif');
    _ganti(id, (p) => _salin(p, aktif: aktif));
  }

  @override
  Future<void> lupakan(String id) async {
    panggilan.add('lupakan $id');
    daftar = [
      for (final p in daftar)
        if (p.id != id) p,
    ];
  }
}

Perangkat _salin(Perangkat p, {String? nama, bool? aktif}) => Perangkat(
  id: p.id,
  nama: nama ?? p.nama,
  aktif: aktif ?? p.aktif,
  terakhirAktif: p.terakhirAktif,
  didaftarkan: p.didaftarkan,
  model: p.model,
  tablet: p.tablet,
  terakhirTarik: p.terakhirTarik,
  jumlahTertahan: p.jumlahTertahan,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  final sekarang = DateTime.now();
  Perangkat hp(
    String id,
    String nama, {
    bool aktif = true,
    Duration diam = const Duration(minutes: 3),
    String? model,
    bool tablet = false,
    Duration? tidakMenarik,
    bool belumPernahMenarik = false,
    int tertahan = 0,
  }) => Perangkat(
    id: id,
    nama: nama,
    aktif: aktif,
    terakhirAktif: sekarang.subtract(diam),
    didaftarkan: DateTime(2026, 6, 12),
    model: model,
    tablet: tablet,
    terakhirTarik: belumPernahMenarik
        ? null
        : sekarang.subtract(tidakMenarik ?? diam),
    jumlahTertahan: tertahan,
  );

  group('masalah data (terakhir_tarik & jumlah_tertahan)', () {
    test('sehat: tidak ada peringatan', () {
      expect(hp('a', 'A').masalahData(sekarang: sekarang), isNull);
      expect(
        hp('a', 'A', tidakMenarik: const Duration(hours: 23))
            .masalahData(sekarang: sekarang),
        isNull,
        reason: 'belum lewat sehari',
      );
    });

    test('ada data tertahan: minta perbarui aplikasi', () {
      final m = hp('a', 'A', tertahan: 12).masalahData(sekarang: sekarang)!;
      expect(m.judul, '12 data tertahan di HP ini');
      expect(m.catatan, contains('Perbarui aplikasi'));
    });

    test('dipakai tapi lebih dari sehari tidak menerima data', () {
      final m = hp('a', 'A', tidakMenarik: const Duration(days: 3, hours: 2))
          .masalahData(sekarang: sekarang)!;
      expect(m.judul, 'Tidak menerima data 3 hari');
      expect(m.catatan, contains('HP ini dipakai'));
    });

    test('belum pernah menerima data (APK lama)', () {
      expect(
        hp('a', 'A', belumPernahMenarik: true)
            .masalahData(sekarang: sekarang)!
            .judul,
        'Belum pernah menerima data',
      );
    });

    test('HP dicabut, atau sudah ditandai diam seminggu: tidak dobel', () {
      expect(
        hp('a', 'A', aktif: false, tertahan: 5).masalahData(sekarang: sekarang),
        isNull,
      );
      final diam = hp('a', 'A', diam: const Duration(days: 9), tertahan: 5);
      expect(diam.masalahData(sekarang: sekarang, idSaya: 'x'), isNull);
      expect(diam.perluPerhatian(sekarang: sekarang, idSaya: 'x'), isTrue);
    });

    test('baris dari server lama tanpa kolom baru terbaca kosong', () {
      final p = Perangkat.dariBaris({
        'id': 'a',
        'nama': 'A',
        'status': 'aktif',
        'terakhir_aktif': '2026-10-23T01:00:00Z',
      });
      expect((p.terakhirTarik, p.jumlahTertahan), (null, 0));
      final baru = Perangkat.dariBaris({
        'id': 'a',
        'status': 'aktif',
        'terakhir_aktif': '2026-10-23T01:00:00Z',
        'terakhir_tarik': '2026-10-22T01:00:00Z',
        'jumlah_tertahan': 4,
      });
      expect(baru.terakhirTarik, DateTime.utc(2026, 10, 22, 1).toLocal());
      expect(baru.jumlahTertahan, 4);
    });
  });

  group('label dan urutan', () {
    final kini = DateTime(2026, 10, 13, 16);
    Perangkat pada(DateTime t) => Perangkat(
      id: 'x',
      nama: 'x',
      aktif: true,
      terakhirAktif: t,
      didaftarkan: t,
    );

    test('perangkat ini "Sedang aktif"; lainnya selalu jam', () {
      final semenit = pada(DateTime(2026, 10, 13, 15, 59));
      expect(
        labelTerakhirAktif(semenit, iniSaya: true, sekarang: kini),
        'Sedang aktif',
      );
      expect(
        labelTerakhirAktif(semenit, iniSaya: false, sekarang: kini),
        'Hari ini, 15:59',
        reason: 'HP lain yang baru sinkron belum tentu masih menyala',
      );
      expect(
        labelTerakhirAktif(
          pada(DateTime(2026, 9, 22, 21, 4)),
          iniSaya: false,
          sekarang: kini,
        ),
        '22 Sep 2026, 21:04',
      );
    });

    test('baris server: dengan & tanpa kolom model (SQL belum jalan)', () {
      final lama = Perangkat.dariBaris({
        'id': 'a',
        'nama': 'HP Kasir',
        'status': 'aktif',
        'terakhir_aktif': '2026-10-13T08:00:00Z',
        'dibuat_pada': '2026-06-12T01:00:00Z',
      });
      expect((lama.model, lama.tablet), (null, false));
      expect(lama.didaftarkan, DateTime.utc(2026, 6, 12, 1).toLocal());
      final baru = Perangkat.dariBaris({
        'id': 'b',
        'nama': 'Tablet',
        'status': 'dicabut',
        'terakhir_aktif': '2026-10-13T08:00:00Z',
        'dibuat_pada': '2026-06-12T01:00:00Z',
        'model': 'Samsung SM-X200 · Android 14',
        'tablet': true,
      });
      expect(
        (baru.model, baru.tablet, baru.aktif),
        ('Samsung SM-X200 · Android 14', true, false),
      );
    });

    test('perangkat ini di atas, lalu terakhir dipakai, dicabut terpisah', () {
      final (aktif, dicabut) = kelompokkanPerangkat([
        hp('lama', 'Lama', diam: const Duration(days: 2)),
        hp('cabut', 'Cabut', aktif: false),
        hp('baru', 'Baru', diam: const Duration(minutes: 1)),
        hp('hp-owner', 'Owner', diam: const Duration(hours: 5)),
      ], 'hp-owner');
      expect(aktif.map((p) => p.id), ['hp-owner', 'baru', 'lama']);
      expect(dicabut.map((p) => p.id), ['cabut']);
    });
  });

  group('halaman', () {
    late _RepoPalsu repo;
    var online = true;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      online = true;
      repo = _RepoPalsu([
        hp('hp-owner', 'HP Owner', model: 'Google Pixel 8a · Android 17'),
        hp(
          'tab',
          'Tablet Kasir Depan',
          model: 'Samsung SM-X200 · Android 14',
          tablet: true,
        ),
        hp('cadangan', 'HP Kasir Cadangan', diam: const Duration(days: 9)),
        hp('dimas', 'HP Lama Dimas', aktif: false),
      ]);
      await SessionManager.instance.setSession(
        AuthSession.create(
          userId: 'o-1',
          username: 'owner',
          role: 'owner',
          shiftId: null,
          permissions: const [],
        ),
      );
    });
    tearDown(() => SessionManager.instance.clearSession());

    void layarHp(WidgetTester t) {
      t.view.physicalSize = const Size(1080, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Future<void> tunggu(WidgetTester t) async {
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pumpAndSettle();
    }

    Future<void> buka(WidgetTester t) async {
      layarHp(t);
      await t.pumpWidget(
        MaterialApp(
          home: DaftarPerangkatPage(repo: repo, cekKoneksi: () async => online),
        ),
      );
      await tunggu(t);
    }

    Future<void> lepas(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    testWidgets('kartu: model, perangkat ini, peringatan, kelompok DICABUT', (
      t,
    ) async {
      await buka(t);
      expect(find.text('Perangkat ini'), findsOneWidget);
      expect(find.text('Sedang aktif'), findsOneWidget);
      expect(find.text('Samsung SM-X200 · Android 14'), findsOneWidget);
      expect(find.byIcon(Icons.tablet_android_rounded), findsOneWidget);
      expect(find.text('Tidak sinkron 9 hari'), findsOneWidget);
      expect(find.text('DICABUT'), findsOneWidget);
      expect(find.text('Dicabut'), findsOneWidget);
      expect(find.text('Aktif'), findsNWidgets(3));
      expect(find.text('12 Jun 2026'), findsNWidgets(4));
      // HP ini tidak bisa dicabut: Cabut hanya di 2 HP aktif lain.
      expect(find.text('Cabut'), findsNWidgets(2));
      expect(find.text('Ganti Nama'), findsNWidgets(4));
      expect(find.text('Pulihkan'), findsOneWidget);
      expect(find.text('Lupakan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('kartu: data terakhir diterima & peringatan data', (t) async {
      repo.daftar = [
        hp('hp-owner', 'HP Owner'),
        hp('kasir-1', 'HP Kasir 1', tertahan: 3),
        hp('kasir-2', 'HP Kasir 2', tidakMenarik: const Duration(days: 2)),
        hp('kasir-3', 'HP Kasir 3', belumPernahMenarik: true),
      ];
      await buka(t);
      expect(find.text('Data terakhir diterima'), findsNWidgets(4));
      expect(find.text('3 data tertahan di HP ini'), findsOneWidget);
      expect(find.text('Tidak menerima data 2 hari'), findsOneWidget);
      expect(find.text('Belum pernah menerima data'), findsOneWidget);
      expect(find.text('Belum ada'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('Cabut ditanya dulu; Batal tidak mengubah apa pun', (t) async {
      await buka(t);
      await t.tap(find.text('Cabut').first);
      await t.pumpAndSettle();
      expect(find.text('Cabut perangkat?'), findsOneWidget);
      expect(
        find.text(
          'Tablet Kasir Depan akan langsung keluar dan tidak bisa mengakses '
          'aplikasi sampai dipulihkan.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();
      expect(repo.panggilan, isEmpty);

      await t.tap(find.text('Cabut').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Cabut').last);
      await tunggu(t);
      expect(repo.panggilan, ['status tab false']);
      expect(find.text('Dicabut'), findsNWidgets(2));
      await lepas(t);
    });

    testWidgets('Pulihkan langsung jalan tanpa konfirmasi', (t) async {
      await buka(t);
      await t.tap(find.text('Pulihkan'));
      await tunggu(t);
      expect(repo.panggilan, ['status dimas true']);
      expect(find.text('DICABUT'), findsNothing);
      await lepas(t);
    });

    testWidgets('Lupakan ditanya dulu, lalu hilang dari daftar', (t) async {
      await buka(t);
      await t.tap(find.text('Lupakan'));
      await t.pumpAndSettle();
      expect(find.text('Lupakan perangkat?'), findsOneWidget);
      expect(
        find.text(
          'HP Lama Dimas akan dihapus permanen dari daftar. Perangkat harus '
          'didaftarkan ulang untuk bisa dipakai.',
        ),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Lupakan').last);
      await tunggu(t);
      expect(repo.panggilan, ['lupakan dimas']);
      expect(find.text('HP Lama Dimas'), findsNothing);
      await lepas(t);
    });

    testWidgets('Ganti Nama: kosong ditolak, nama baru tersimpan', (t) async {
      await buka(t);
      await t.tap(find.text('Ganti Nama').at(1));
      await t.pumpAndSettle();
      expect(find.text('Ganti Nama Perangkat'), findsOneWidget);
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.text('Simpan'));
      await t.pump();
      expect(find.text('Nama perangkat wajib diisi'), findsOneWidget);
      expect(repo.panggilan, isEmpty);

      await t.enterText(find.byType(TextField), ' Tablet  Depan ');
      await t.tap(find.text('Simpan'));
      await tunggu(t);
      expect(repo.panggilan, ['nama tab Tablet Depan']);
      expect(find.text('Tablet Depan'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('Ganti Nama tanpa perubahan tidak mengirim apa pun', (t) async {
      await buka(t);
      await t.tap(find.text('Ganti Nama').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Simpan'));
      await tunggu(t);
      expect(repo.panggilan, isEmpty);
      await lepas(t);
    });

    testWidgets('tanpa internet: layar offline, Coba lagi memuat daftar', (
      t,
    ) async {
      online = false;
      await buka(t);
      expect(find.text('Tidak ada koneksi internet'), findsOneWidget);
      expect(find.text('HP Owner'), findsNothing);
      online = true;
      await t.tap(find.text('Coba lagi'));
      await tunggu(t);
      expect(find.text('HP Owner'), findsOneWidget);
      await lepas(t);
    });

    testWidgets('kosong: "Belum ada perangkat terdaftar"', (t) async {
      repo.daftar = [];
      await buka(t);
      expect(find.text('Belum ada perangkat terdaftar'), findsOneWidget);
      await lepas(t);
    });
  });
}
