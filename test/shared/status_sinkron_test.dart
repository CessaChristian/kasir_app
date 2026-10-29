import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/sync/sync_service.dart';
import 'package:kasir_app/shared/ui/status_sinkron.dart';

/// Sinkron yang macet tidak boleh lagi diam: data tertahan atau sinkron yang
/// lama tidak berhasil tampil sebagai peringatan oranye.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  final kini = DateTime(2026, 10, 22, 15);

  group('peringatanSinkron', () {
    test('normal: tidak ada peringatan', () {
      expect(
        peringatanSinkron(
          tertahan: 0,
          terakhirBerhasil: kini.subtract(const Duration(minutes: 29)),
          sekarang: kini,
        ),
        isNull,
      );
    });

    test('ada data tertahan: minta perbarui aplikasi', () {
      expect(
        peringatanSinkron(tertahan: 12, terakhirBerhasil: kini, sekarang: kini),
        '12 data dari server belum bisa disimpan di HP ini. '
        'Perbarui aplikasi ke versi terbaru.',
      );
    });

    test('QA S10: ada data yang ditolak server: hubungi owner', () {
      expect(
        peringatanSinkron(
          tertahan: 0,
          gagalKirim: 3,
          terakhirBerhasil: kini,
          sekarang: kini,
        ),
        '3 data dari HP ini ditolak server dan belum terkirim. '
        'Beri tahu owner.',
      );
    });

    test('lebih dari 30 menit belum berhasil: data mungkin basi', () {
      expect(
        peringatanSinkron(
          tertahan: 0,
          terakhirBerhasil: DateTime(2026, 10, 22, 14, 20),
          sekarang: kini,
        ),
        'Sinkron terakhir 14:20 — data di HP ini mungkin belum terbaru. '
        'Periksa internet lalu tarik layar untuk menyegarkan.',
      );
      expect(
        peringatanSinkron(tertahan: 0, terakhirBerhasil: null, sekarang: kini),
        startsWith('Belum pernah sinkron —'),
      );
    });
  });

  group('StatusSinkron', () {
    final sync = SyncService.instance;
    tearDown(() {
      sync.jumlahTertahan.value = 0;
      sync.terakhirBerhasil.value = null;
    });

    Future<void> pasang(WidgetTester t, {bool hanyaPeringatan = false}) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(body: StatusSinkron(hanyaPeringatan: hanyaPeringatan)),
        ));

    testWidgets('normal: label abu-abu biasa', (t) async {
      sync.terakhirBerhasil.value = DateTime.now();
      await pasang(t);
      expect(find.textContaining('Sinkron terakhir'), findsOneWidget);
      expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
    });

    testWidgets('Dashboard owner: diam kalau normal', (t) async {
      sync.terakhirBerhasil.value = DateTime.now();
      await pasang(t, hanyaPeringatan: true);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('baris tertahan bertambah: langsung jadi peringatan', (
      t,
    ) async {
      sync.terakhirBerhasil.value = DateTime.now();
      await pasang(t, hanyaPeringatan: true);
      sync.jumlahTertahan.value = 3;
      await t.pump();
      expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
      expect(find.textContaining('3 data dari server'), findsOneWidget);
    });

    testWidgets('jadi basi seiring waktu tanpa sinkron baru', (t) async {
      // Tepat di ambang 30 menit; detak berikutnya sudah melewatinya.
      sync.terakhirBerhasil.value = DateTime.now().subtract(
        const Duration(minutes: 29, seconds: 59, milliseconds: 900),
      );
      await pasang(t);
      expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      // Detak satu menit, tanpa kejadian apa pun.
      await t.pump(const Duration(minutes: 1));
      expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
    });
  });
}
