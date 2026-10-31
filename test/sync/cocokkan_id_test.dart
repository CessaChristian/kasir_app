import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';
import 'package:kasir_app/data/sync/sync_engine.dart';
import 'package:kasir_app/data/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA kedua S12 — HP yang lama dicabut lalu dipulihkan masih menyimpan
/// produk yang sudah dibuang permanen di server. Tarikan biasa hanya membawa
/// baris yang BERUBAH; baris yang sudah tidak ada tidak pernah datang, jadi
/// produknya tetap bisa dijual — dan kalau diedit, hidup lagi di server.
class _RepoTiruan extends PerangkatRepository {
  _RepoTiruan() : super.untukTest();
  StatusPerangkatIni jawaban = StatusPerangkatIni.dicabut;
  @override
  Future<StatusPerangkatIni> statusSaya() async => jawaban;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> produk(String id, {String status = 'synced'}) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: Value(id),
          name: id,
          price: 1000,
          syncStatus: Value(status),
        ),
      );

  Future<Product> baca(String id) =>
      (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();

  SyncEngine mesin(Map<String, List<String>> server) =>
      SyncEngine(db)
        ..daftarIdServerUntukTest = (tabel) async => server[tabel] ?? const [];

  test('produk yang sudah tidak ada di server disembunyikan; yang belum '
      'terkirim dibiarkan', () async {
    await produk('es-teh');
    await produk('latte');
    await produk('baru', status: 'pending');
    final n = await mesin({
      'products': ['latte'],
      'categories': [],
    }).cocokkanId();
    expect(n, 1);
    expect((await baca('es-teh')).deletedAt, isNotNull);
    expect(
      (await baca('es-teh')).syncStatus,
      'synced',
      reason: 'tidak dikirim balik ke server',
    );
    expect((await baca('latte')).deletedAt, isNull);
    expect((await baca('baru')).deletedAt, isNull);
  });

  test('server menjawab kosong padahal HP punya data: tidak ada yang '
      'disentuh', () async {
    await produk('latte');
    expect(await mesin({}).cocokkanId(), 0);
    expect((await baca('latte')).deletedAt, isNull);
  });

  test(
    'HP dipulihkan owner: pencocokan diminta pada sinkron berikutnya',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_cocokkan_id_terakhir': DateTime.now().toIso8601String(),
      });
      final repo = _RepoTiruan();
      await repo.periksaStatusSaya();
      expect(
        await SyncService.perluCocokkanId(),
        isFalse,
        reason: 'baru dicabut — belum dipulihkan',
      );
      repo.jawaban = StatusPerangkatIni.aktif;
      await repo.periksaStatusSaya();
      expect(await SyncService.perluCocokkanId(), isTrue);
    },
  );

  test(
    'tanpa pemulihan: tetap dicocokkan paling lambat seminggu sekali',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_cocokkan_id_terakhir': DateTime.now()
            .subtract(const Duration(days: 8))
            .toIso8601String(),
      });
      expect(await SyncService.perluCocokkanId(), isTrue);
      SharedPreferences.setMockInitialValues({
        'sync_cocokkan_id_terakhir': DateTime.now().toIso8601String(),
      });
      expect(await SyncService.perluCocokkanId(), isFalse);
    },
  );

  group('review R8: daftar id server harus lengkap', () {
    final ids = [
      for (var i = 0; i < 1500; i++) 'p-${i.toString().padLeft(4, '0')}',
    ];

    SyncEngine server({required int batasJawaban, int? jumlah}) =>
        SyncEngine(db)
          ..jumlahServerUntukTest = ((t) async =>
              t == 'products' ? jumlah ?? ids.length : 0)
          ..halamanIdUntukTest = (t, dari, sampai) async {
            if (t != 'products' || dari >= ids.length) return const [];
            final akhir = [
              sampai + 1,
              dari + batasJawaban,
              ids.length,
            ].reduce((a, b) => a < b ? a : b);
            return ids.sublist(dari, akhir);
          };

    test('server menjawab paling banyak 500 per permintaan: tidak ada produk '
        'yang disembunyikan', () async {
      await produk('p-1200');
      await produk('hilang');
      expect(await server(batasJawaban: 500).cocokkanId(), 1);
      expect((await baca('p-1200')).deletedAt, isNull);
      expect((await baca('hilang')).deletedAt, isNotNull);
    });

    test('jumlah id tidak sama dengan hitungan server: tidak membersihkan '
        'apa pun', () async {
      await produk('p-1200');
      await produk('hilang');
      expect(await server(batasJawaban: 1000, jumlah: 1600).cocokkanId(), 0);
      expect((await baca('hilang')).deletedAt, isNull);
    });
  });
}
