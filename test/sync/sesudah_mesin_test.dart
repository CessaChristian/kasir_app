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
}
