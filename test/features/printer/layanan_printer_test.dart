import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/printer/data/layanan_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tiruan implements SaluranPrinter {
  bool nyala = true;
  bool izin = true;
  bool tersambungAwal = false;
  bool bisaSambung = true;

  /// Kiriman ke-n (mulai 1) yang gagal.
  Set<int> kirimGagal = {};

  /// Sambung tidak pernah selesai (printer mati, Bluetooth menunggu).
  bool sambungMenggantung = false;

  /// Lama sambung & kirim (printer lemot).
  Duration jedaSambung = Duration.zero;
  Duration jedaKirim = Duration.zero;

  final catatan = <String>[];
  var _kirim = 0;
  bool _tersambung = false;

  @override
  Future<bool> bluetoothNyala() async => nyala;
  @override
  Future<bool> izinAda() async => izin;
  @override
  Future<List<PrinterTerpasang>> terpasang() async => [
    (nama: 'RPP02N', mac: '86:67:7A:80:4E:3D'),
  ];
  @override
  Future<void> bukaPengaturanBluetooth() async =>
      catatan.add('buka pengaturan');
  @override
  Future<void> bukaPengaturanIzin() async => catatan.add('buka izin');
  @override
  Future<bool> tersambung() async => tersambungAwal || _tersambung;
  @override
  Future<bool> sambung(String mac) {
    catatan.add('sambung $mac');
    if (sambungMenggantung) return Completer<bool>().future;
    return Future.delayed(jedaSambung, () {
      _tersambung = bisaSambung;
      return bisaSambung;
    });
  }

  @override
  Future<bool> kirim(List<int> bytes) async {
    _kirim++;
    catatan.add('kirim ${bytes.length}');
    final ke = _kirim;
    await Future<void>.delayed(jedaKirim);
    return !kirimGagal.contains(ke);
  }

  @override
  Future<void> putus() async {
    catatan.add('putus');
    _tersambung = false;
    tersambungAwal = false;
  }
}

void main() {
  late _Tiruan t;
  late LayananPrinter l;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    t = _Tiruan();
    l = LayananPrinter.untukTest(t);
    await l.simpan(
      const PengaturanPrinter(mac: '86:67:7A:80:4E:3D', nama: 'RPP02N'),
    );
  });

  test('pengaturan bawaan: belum ada printer', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await l.muat()).dipilih, isFalse);
  });

  test('ganti printer: sambungan lama diputus, struk ke printer BARU '
      '(dulu tetap keluar di printer lama)', () async {
    expect(await l.cetak([1]), HasilCetak.berhasil);
    await l.simpan(const PengaturanPrinter(mac: 'AA:BB', nama: 'Lain'));
    t.catatan.clear();
    expect(await l.cetak([2, 2]), HasilCetak.berhasil);
    expect(t.catatan, ['putus', 'sambung AA:BB', 'kirim 2']);
  });

  test('printer belum dipilih / Bluetooth mati / tanpa izin', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await l.cetak([1]), HasilCetak.belumDipilih);
    await l.simpan(const PengaturanPrinter(mac: 'x', nama: 'x'));
    t.nyala = false;
    expect(await l.cetak([1]), HasilCetak.bluetoothMati);
    t
      ..nyala = true
      ..izin = false;
    expect(await l.cetak([1]), HasilCetak.tanpaIzin);
    expect(t.catatan, isEmpty, reason: 'printer tidak disentuh');
  });

  test('tersambung → kirim', () async {
    expect(await l.cetak([1, 2, 3]), HasilCetak.berhasil);
    expect(t.catatan, ['putus', 'sambung 86:67:7A:80:4E:3D', 'kirim 3']);
  });

  test(
    'sambungan lama sudah mati: kirim gagal → sambung ulang sekali',
    () async {
      expect(await l.cetak([1]), HasilCetak.berhasil); // tersambung
      t
        ..kirimGagal = {2}
        ..catatan.clear();
      expect(await l.cetak([1]), HasilCetak.berhasil);
      expect(t.catatan, [
        'kirim 1',
        'putus',
        'sambung 86:67:7A:80:4E:3D',
        'kirim 1',
      ]);
    },
  );

  test('printer mati: tidak tersambung, tanpa mencoba sambung lagi — '
      'kasir cepat tahu', () async {
    t.bisaSambung = false;
    expect(await l.cetak([1]), HasilCetak.takTersambung);
    expect(t.catatan.where((c) => c.startsWith('sambung')).length, 1);
    expect(
      pesanCetak(HasilCetak.takTersambung),
      contains('Printer tidak tersambung'),
    );
  });

  test('sambungan menggantung: menyerah sesudah batas satu langkah '
      '(7 detik)', () {
    fakeAsync((w) {
      t.sambungMenggantung = true;
      HasilCetak? h;
      l.cetak([1]).then((x) => h = x);
      w.elapse(const Duration(seconds: 6));
      expect(h, isNull);
      w.elapse(const Duration(seconds: 2));
      expect(h, HasilCetak.takTersambung);
    });
  });

  test('lewat batas waktu: cetakan lama tidak lagi mencetak, dan ketukan '
      'berikutnya menunggu giliran — tidak ada struk dobel', () {
    fakeAsync((w) {
      final lemot = LayananPrinter.untukTest(
        t,
        batasCetak: const Duration(seconds: 1),
      );
      t.jedaSambung = const Duration(seconds: 3);
      HasilCetak? pertama;
      lemot.cetak([1]).then((x) => pertama = x);
      w.elapse(const Duration(milliseconds: 1100));
      expect(pertama, HasilCetak.takTersambung);

      // Kasir langsung mengetuk Cetak lagi; printernya kini cepat.
      HasilCetak? kedua;
      lemot.cetak([2, 2]).then((x) => kedua = x);
      t.jedaSambung = Duration.zero;
      w.elapse(const Duration(seconds: 3));
      expect(kedua, HasilCetak.berhasil);
      expect(t.catatan.where((c) => c.startsWith('kirim')), ['kirim 2'],
          reason: 'cetakan pertama yang akhirnya tersambung tidak mengirim');
      expect(t.catatan, [
        'putus', 'sambung 86:67:7A:80:4E:3D', 'putus', // pertama berhenti
        'putus', 'sambung 86:67:7A:80:4E:3D', 'kirim 2', // baru giliran kedua
      ], reason: 'sambungan kedua tidak diputus cetakan pertama yang telat');
    });
  });

  test('lewat batas waktu saat struk sedang dikirim: "mungkin sudah '
      'tercetak", bukan "tidak tersambung"', () {
    fakeAsync((w) {
      final lemot = LayananPrinter.untukTest(
        t,
        batasCetak: const Duration(seconds: 1),
      );
      t.jedaKirim = const Duration(seconds: 3);
      HasilCetak? h;
      lemot.cetak([1]).then((x) => h = x);
      w.elapse(const Duration(milliseconds: 1100));
      expect(h, HasilCetak.mungkinTercetak);
      expect(pesanCetak(h!), contains('Cek printer sebelum cetak ulang'));
      w.elapse(const Duration(seconds: 5));
    });
  });

  test('dua ketukan beruntun: dicetak bergiliran, tidak bercampur', () async {
    final a = l.cetak([1]);
    final b = l.cetak([2, 2]);
    expect(await Future.wait([a, b]), [
      HasilCetak.berhasil,
      HasilCetak.berhasil,
    ]);
    expect(t.catatan.where((c) => c.startsWith('kirim')), [
      'kirim 1',
      'kirim 2',
    ]);
  });

  test('sambungan baru: tunggu sebentar sebelum kirim — byte awal tidak '
      'hilang (logo cetakan pertama miring)', () {
    fakeAsync((w) {
      final lambat = LayananPrinter.untukTest(
        t,
        jedaSesudahSambung: const Duration(milliseconds: 600),
      );
      HasilCetak? h;
      lambat.cetak([1]).then((x) => h = x);
      w.flushMicrotasks();
      w.elapse(const Duration(milliseconds: 100));
      expect(t.catatan, ['putus', 'sambung 86:67:7A:80:4E:3D'],
          reason: 'belum dikirim');
      w.elapse(const Duration(milliseconds: 600));
      expect(t.catatan.last, 'kirim 1');
      expect(h, HasilCetak.berhasil);
    });
  });

  test('periksa: printer menyala → true, sambungannya dipakai cetakan '
      'berikutnya (tanpa sambung ulang)', () async {
    expect(await l.periksa(), isTrue);
    expect(t.catatan, ['putus', 'sambung 86:67:7A:80:4E:3D']);
    t.catatan.clear();
    expect(await l.cetak([1]), HasilCetak.berhasil);
    expect(t.catatan, ['kirim 1']);
  });

  test('periksa: printer mati → false (walau tetap ada di daftar Android)',
      () async {
    t.bisaSambung = false;
    expect(await l.periksa(), isFalse);
  });

  test('periksa: belum ada printer dipilih → false tanpa menyentuh printer',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(await l.periksa(), isFalse);
    expect(t.catatan, isEmpty);
  });
}
