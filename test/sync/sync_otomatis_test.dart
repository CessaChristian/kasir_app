import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/sync/sync_otomatis.dart';

/// Mengunci aturan kapan sinkronisasi otomatis BOLEH dan TIDAK BOLEH jalan.
///
/// Latar belakangnya masalah harga basi: pemilik mengubah harga dari HP-nya,
/// HP kasir tetap memakai harga lama sampai ada yang ingat menyegarkan.
/// Sinkron otomatis menutup jendela itu — tapi ia tidak boleh menutupnya
/// dengan mengacaukan pekerjaan kasir.
void main() {
  final s = SyncOtomatis.instance;
  final sekarang = DateTime(2026, 9, 5, 14, 0);

  setUp(() => s.resetUntukTest());
  tearDown(() => s.resetUntukTest());

  test('boleh jalan saat keranjang kosong dan belum pernah sinkron', () {
    expect(s.alasanDilewati(sekarang: sekarang), isNull);
  });

  test('DITUNDA selagi kasir menyusun pesanan', () {
    // Daftar produk di halaman kasir menyala langsung dari database, jadi
    // sinkron di tengah pesanan mengubah grid tepat di bawah jari kasir:
    // harga berganti, atau produk lenyap karena dihapus pemilik.
    s.sedangMenyusunPesanan = true;

    expect(s.alasanDilewati(sekarang: sekarang), 'keranjang sedang berisi');
  });

  // Form produk yang terbuka menahan sinkron dengan alasan yang sama seperti
  // keranjang: ada pekerjaan setengah jadi yang belum tercatat di database.
  // Bedanya, yang dipertaruhkan di sini berkas foto — sinkron gambar membuang
  // berkas yang belum dirujuk baris mana pun.
  test('DITUNDA selagi form produk terbuka', () {
    s.sedangMenyuntingProduk = true;
    expect(s.alasanDilewati(sekarang: sekarang), 'form produk sedang terbuka');
    expect(
      s.alasanDilewati(sekarang: sekarang, abaikanJeda: true),
      'form produk sedang terbuka',
      reason: 'kembali aktif dari galeri tidak boleh menembus penjaga ini — '
          'justru di situlah fotonya paling rawan dibuang',
    );
  });

  test('jeda minimum mencegah sinkron beruntun saat berpindah halaman',
      () async {
    await s.picu('halaman kasir dibuka');

    expect(
      s.alasanDilewati(sekarang: DateTime.now()),
      'baru saja sinkron',
      reason: 'tanpa jeda ini, membuka-tutup halaman kasir menembak satu '
          'putaran sinkron setiap kali',
    );
  });

  test('kembali aktif dari latar belakang MENGABAIKAN jeda minimum', () async {
    // HP kasir tidur di antara pelanggan. Timer ikut berhenti saat layar mati,
    // jadi saat dibangunkan datanya bisa sudah berjam-jam basi. Menolak
    // sinkron di momen itu hanya karena "baru saja" justru mempertahankan
    // kebasiannya.
    await s.picu('sesuatu');

    expect(
      s.alasanDilewati(sekarang: DateTime.now(), abaikanJeda: true),
      isNull,
    );
  });

  test('keranjang berisi tetap menang atas abaikanJeda', () async {
    s.sedangMenyusunPesanan = true;

    expect(
      s.alasanDilewati(sekarang: sekarang, abaikanJeda: true),
      'keranjang sedang berisi',
      reason: 'tidak ada alasan yang cukup penting untuk mengubah grid di '
          'tengah kasir menyusun pesanan',
    );
  });

  // ── PERUBAHAN LOKAL LANGSUNG DIKIRIM ──
  //
  // Dulu perangkat yang MENGUBAH data ikut menunggu putaran lima menit, jadi
  // pemilik harus menyegarkan HP-nya sendiri hanya supaya perubahannya naik ke
  // server. Itu terbalik: yang mengubah seharusnya mengirim, yang ingin tahu
  // yang menyegarkan.

  group('perubahan lokal memicu kiriman', () {
    test('beruntun digabung jadi SATU kiriman', () {
      fakeAsync((waktu) {
        var kirim = 0;
        s.penggantiPicuUntukTest = (_) async => kirim++;

        // Pemilik menghapus lima produk beruntun.
        for (var i = 0; i < 5; i++) {
          s.adaPerubahanLokal();
          waktu.elapse(const Duration(milliseconds: 500));
        }
        expect(kirim, 0,
            reason: 'selama perubahan masih berdatangan, jedanya diulang');

        waktu.elapse(SyncOtomatis.jedaGabung + const Duration(seconds: 1));
        expect(kirim, 1,
            reason: 'lima penghapusan cukup satu perjalanan — satu kiriman '
                'membawa SEMUA baris yang tertunda, bukan satu baris');
      });
    });

    test('perubahan tunggal terkirim setelah jeda, bukan menunggu lima menit',
        () {
      fakeAsync((waktu) {
        var kirim = 0;
        s.penggantiPicuUntukTest = (_) async => kirim++;

        s.adaPerubahanLokal();
        waktu.elapse(SyncOtomatis.jedaGabung - const Duration(seconds: 1));
        expect(kirim, 0, reason: 'belum sampai jedanya');

        waktu.elapse(const Duration(seconds: 2));
        expect(kirim, 1);
      });
    });

    test('jedanya jauh lebih pendek dari putaran berkala', () {
      expect(SyncOtomatis.jedaGabung, lessThan(SyncOtomatis.jarakBerkala),
          reason: 'kalau tidak, HP lain yang menyegarkan sedetik kemudian '
              'tetap melihat data lama — tujuan perubahan ini hilang');
    });
  });

  // ── PENJAGA LINGKARAN ──
  //
  // Sinkron sendiri menulis ke tabel saat menyimpan data dari server. Tanpa
  // penjaga ini, tulisan itu dianggap perubahan lokal dan memicu sinkron
  // berikutnya: tarik -> tulis -> picu -> tarik, tanpa henti.
  group('tulisan dari sinkron tidak boleh memicu apa-apa', () {
    test('selagi sinkron berjalan, tulisan diabaikan', () {
      expect(
        s.perluKirimSetelahTulisan(
          tabel: {'products'},
          sinkronSedangJalan: true,
        ),
        isFalse,
      );
    });

    test('di luar sinkron, tulisan pengguna ditanggapi', () {
      expect(
        s.perluKirimSetelahTulisan(
          tabel: {'products'},
          sinkronSedangJalan: false,
        ),
        isTrue,
      );
    });

    test('penanda sync_state saja TIDAK ditanggapi, walau sinkron sudah usai',
        () {
      // Kabar tulisan datang lewat antrean, jadi bisa tiba setelah penanda
      // "sedang sinkron" mati. Tanpa aturan ini, setiap putaran menjadwalkan
      // putaran berikutnya — tiga detik sekali, selamanya.
      expect(
        s.perluKirimSetelahTulisan(
          tabel: {'sync_state'},
          sinkronSedangJalan: false,
        ),
        isFalse,
      );
    });

    test('tulisan campuran tetap ditanggapi', () {
      expect(
        s.perluKirimSetelahTulisan(
          tabel: {'sync_state', 'transactions'},
          sinkronSedangJalan: false,
        ),
        isTrue,
        reason: 'ada transaksi sungguhan di dalamnya',
      );
    });
  });

  test('jarak berkala lebih rapat dari batas basi', () {
    // Kalau timernya lebih jarang daripada ambang "basi", label peringatan
    // akan menyala di keadaan normal dan kasir belajar mengabaikannya.
    expect(SyncOtomatis.jarakBerkala, lessThan(SyncOtomatis.batasBasi));
  });

  test('jeda minimum lebih rapat dari jarak berkala', () {
    // Kalau terbalik, sinkron berkala akan menolak dirinya sendiri.
    expect(SyncOtomatis.jedaMinimum, lessThan(SyncOtomatis.jarakBerkala));
  });
}
