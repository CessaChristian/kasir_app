import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/periode/pengawas_hari.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';

/// Halaman yang dibiarkan terbuka lewat tengah malam (revisi QA, temuan K3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geserPintasan', () {
    final kemarin = DateTime(2026, 10, 27);
    final hariIni = DateTime(2026, 10, 28);

    test('pintasan ikut pindah ke tanggal baru', () {
      expect(
        geserPintasan(Periode.hari(kemarin), kemarin, hariIni),
        Periode.hari(hariIni),
      );
      expect(
        geserPintasan(
          Periode(DateTime(2026, 10, 21), kemarin),
          kemarin,
          hariIni,
        ),
        Periode(DateTime(2026, 10, 22), hariIni),
        reason: '7 Hari Terakhir',
      );
    });

    test('ganti bulan: Bulan Ini jadi bulan yang baru', () {
      final akhirOkt = DateTime(2026, 10, 31);
      final awalNov = DateTime(2026, 11, 1);
      // 1 Okt – 31 Okt di tanggal 31 Okt = "Bulan Ini".
      expect(
        geserPintasan(
          Periode(DateTime(2026, 10, 1), akhirOkt),
          akhirOkt,
          awalNov,
        ),
        Periode.hari(awalNov),
      );
    });

    test('rentang pilihan sendiri tidak digeser', () {
      expect(
        geserPintasan(
          Periode(DateTime(2026, 10, 3), DateTime(2026, 10, 9)),
          kemarin,
          hariIni,
        ),
        isNull,
      );
    });
  });

  test('pengawas bangun sesudah tengah malam, sekali saja', () {
    fakeAsync((async) {
      final mulai = DateTime(2026, 10, 27, 23, 58);
      DateTime jam() => mulai.add(async.elapsed);
      final ganti = <(DateTime, DateTime)>[];
      final p = PengawasHari(
        jam: jam,
        onGanti: (lama, baru) => ganti.add((lama, baru)),
      );

      async.elapse(const Duration(minutes: 1));
      expect(ganti, isEmpty, reason: 'masih 23.59');

      async.elapse(const Duration(minutes: 2));
      expect(ganti, [(DateTime(2026, 10, 27), DateTime(2026, 10, 28))]);

      async.elapse(const Duration(hours: 12));
      expect(ganti, hasLength(1));
      p.dispose();
    });
  });

  test(
    'periksa() saat aplikasi kembali ke depan menangkap hari yang lewat',
    () {
      var sekarang = DateTime(2026, 10, 27, 22);
      final ganti = <DateTime>[];
      final p = PengawasHari(
        jam: () => sekarang,
        onGanti: (_, baru) => ganti.add(baru),
      );
      sekarang = DateTime(2026, 10, 28, 7);
      p.periksa();
      expect(ganti, [DateTime(2026, 10, 28)]);
      p.dispose();
    },
  );
}
