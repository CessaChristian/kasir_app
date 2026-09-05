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
