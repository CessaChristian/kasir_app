import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/data/sync/sync_service.dart';

/// Satu baris yang ditolak server tidak boleh menghentikan kabar "HP ini
/// masih aktif" dan pemeriksaan akun/izin/shift sesudah sinkron.
void main() {
  late List<String> urutan;

  Future<HasilSync> jalankan(
    HasilSync hasil, {
    Object? galatPemeriksaan,
  }) =>
      SyncService.urutanSesudahMesin(
        hasil,
        hanyaKalauBerhasil: () async {
          urutan.add('foto & catat berhasil');
          return const HasilSync(didorong: 9);
        },
        selamaTersambung: () async {
          urutan.add('periksa & lapor aktif');
          if (galatPemeriksaan != null) throw galatPemeriksaan;
        },
      );

  setUp(() => urutan = []);

  test('putaran bersih: semuanya jalan, hasil lengkap dipakai', () async {
    final h = await jalankan(const HasilSync());
    expect(urutan, ['foto & catat berhasil', 'periksa & lapor aktif']);
    expect(h.didorong, 9);
  });

  test('ada baris ditolak server: tetap lapor aktif & periksa akun/shift',
      () async {
    const gagal = HasilSync(error: 'baris ditolak');
    final h = await jalankan(gagal);
    expect(urutan, ['periksa & lapor aktif']);
    expect(identical(h, gagal), isTrue, reason: 'galat asli tetap dilaporkan');
  });

  test('QA S10: baris ditolak tapi tarikan selesai — foto & buang sampah '
      'tetap jalan, galatnya tetap dilaporkan', () async {
    const gagal = HasilSync(
      error: 'products: ditolak',
      tarikSelesai: true,
      ditolak: 2,
    );
    await jalankan(gagal);
    expect(urutan, ['foto & catat berhasil', 'periksa & lapor aktif']);
  });

  for (final (nama, h) in const [
    ('koneksi putus', HasilSync(error: 'x', tarikSelesai: true, koneksiPutus: true)),
    ('dibatalkan', HasilSync(error: 'x', tarikSelesai: true, dibatalkan: true)),
  ]) {
    test('QA S10: $nama — foto tidak dicoba', () async {
      await jalankan(h);
      expect(urutan, ['periksa & lapor aktif']);
    });
  }

  test('putaran gagal & pemeriksaannya ikut gagal: galat asli tidak tertimpa',
      () async {
    const gagal = HasilSync(error: 'baris ditolak');
    final h = await jalankan(gagal, galatPemeriksaan: StateError('kueri'));
    expect(h.error, 'baris ditolak');
  });

  group('tarikan bersih (patokan buang sampah)', () {
    test('semua tabel tertarik, tidak ada yang tertahan: bersih', () {
      expect(
        SyncService.tarikBersih(const HasilSync(tarikSelesai: true), 0),
        isTrue,
      );
    });

    test('ada baris tertahan: TIDAK bersih walau tarikannya selesai', () {
      expect(
        SyncService.tarikBersih(const HasilSync(tarikSelesai: true), 3),
        isFalse,
      );
    });

    test('tarikan putus di tengah: tidak bersih', () {
      expect(
        SyncService.tarikBersih(
          const HasilSync(error: 'tarik: putus', tarikSelesai: false),
          0,
        ),
        isFalse,
      );
    });

    test('hanya kiriman yang gagal: tetap bersih — HP sudah menerima semua', () {
      expect(
        SyncService.tarikBersih(
          const HasilSync(error: 'products: ditolak', tarikSelesai: true),
          0,
        ),
        isTrue,
      );
    });

    test('tanda tarikan ikut terbawa saat hasil foto digabungkan', () {
      const h = HasilSync(tarikSelesai: true);
      expect(h.denganGambar(naik: 1).tarikSelesai, isTrue);
    });
  });

  group('QA K10: data yang ditulis selagi sinkron berjalan', () {
    const bersih = HasilSync(tarikSelesai: true, ditolak: 0);
    test('masih ada yang tertunda: diulang sekali', () {
      expect(SyncService.perluUlang(bersih, 1), isTrue);
    });
    test('tidak ada yang tertunda: tidak diulang', () {
      expect(SyncService.perluUlang(bersih, 0), isFalse);
    });
    test('yang tertunda hanya baris yang ditolak server: tidak diulang '
        '(tidak berputar tanpa henti)', () {
      const ditolak = HasilSync(
          error: 'x', tarikSelesai: true, ditolak: 2);
      expect(SyncService.perluUlang(ditolak, 2), isFalse);
      expect(SyncService.perluUlang(ditolak, 3), isTrue);
    });
    test('koneksi putus atau dibatalkan: tidak diulang', () {
      expect(
        SyncService.perluUlang(
            const HasilSync(error: 'x', tarikSelesai: true, koneksiPutus: true),
            5),
        isFalse,
      );
      expect(
        SyncService.perluUlang(
            const HasilSync(error: 'x', tarikSelesai: true, dibatalkan: true),
            5),
        isFalse,
      );
    });
  });
}
