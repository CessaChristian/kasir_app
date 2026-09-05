import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_service.dart';

/// Menjalankan sinkronisasi dengan sendirinya, tanpa pengguna perlu menarik
/// layar.
///
/// ── MASALAH YANG DIPECAHKAN ──
///
/// Sebelum ini sinkronisasi hanya berjalan saat aplikasi dibuka dan saat
/// pengguna menarik layar. Kalau pemilik mengubah harga dari HP-nya, HP kasir
/// tetap memakai harga LAMA sampai ada yang ingat menyegarkan — bisa
/// berjam-jam. Pelanggan terlanjur dibayar dengan harga yang salah, dan tidak
/// ada satu pun tanda bahwa itu sedang terjadi.
///
/// Mengandalkan pemilik memberi tahu kasir setiap kali mengubah harga bukan
/// jawaban: justru pada jam ramai — saat harga salah paling banyak terpakai —
/// pemberitahuan itu paling mungkin terlupa, dan pemilik belum tentu berada
/// di ruangan yang sama.
///
/// ── KENAPA "KEMBALI AKTIF" LEBIH PENTING DARIPADA TIMER ──
///
/// HP kasir tidur di antara pelanggan. Timer di dalam aplikasi ikut berhenti
/// saat layar mati, jadi saat dibangunkan datanya bisa sudah berjam-jam basi
/// sementara timernya baru menghitung dari nol. Menyinkronkan tepat saat
/// aplikasi kembali aktif menutup jendela itu, dan justru pada momen kasir
/// mulai melayani.
class SyncOtomatis with WidgetsBindingObserver {
  SyncOtomatis._();
  static final SyncOtomatis instance = SyncOtomatis._();

  /// Jarak antar sinkronisasi berkala selagi aplikasi ada di depan.
  ///
  /// Lebih rapat dari kelaziman industri (10–30 menit) karena satu putaran
  /// dengan penanda posisi yang tepat mengembalikan NOL baris dan sangat
  /// murah. Kalau kuota jadi masalah, cukup ubah angka ini.
  static const jarakBerkala = Duration(minutes: 5);

  /// Sinkron yang jaraknya lebih dekat dari ini dilewati.
  ///
  /// Tanpa jeda ini, berpindah-pindah halaman memicu putaran beruntun: setiap
  /// kali halaman kasir dibuka akan menembak satu sinkron lagi.
  static const jedaMinimum = Duration(minutes: 2);

  /// Dianggap basi kalau sudah selama ini tidak berhasil sinkron.
  static const batasBasi = Duration(minutes: 30);

  Timer? _timer;
  DateTime? _percobaanTerakhir;
  bool _tertunda = false;

  /// Diisi halaman kasir: true selagi ada isi di keranjang.
  ///
  /// Daftar produk di halaman kasir menyala langsung dari database
  /// (`StreamBuilder`), jadi sinkron di tengah pesanan mengubah grid TEPAT di
  /// bawah jari kasir — harga berganti, atau produk lenyap karena dihapus
  /// pemilik. Harga yang sudah masuk keranjang memang terkunci, tapi
  /// perbedaan antara grid dan keranjang itu sendiri yang membingungkan.
  ///
  /// Maka sinkron ditunda sampai keranjang kosong. Supaya penundaan itu tidak
  /// berkepanjangan pada jam ramai, [lanjutkanYangTertunda] dipanggil begitu
  /// transaksi selesai — momen paling aman untuk menyegarkan.
  bool sedangMenyusunPesanan = false;

  void mulai() {
    WidgetsBinding.instance.addObserver(this);
    _nyalakanTimer();
  }

  @visibleForTesting
  void berhenti() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  void _nyalakanTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(jarakBerkala, (_) => picu('berkala'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nyalakanTimer();
      // Sengaja mengabaikan jeda minimum: jendela basi setelah HP tidur bisa
      // berjam-jam, dan inilah satu-satunya kesempatan menutupnya sebelum
      // kasir melayani pelanggan berikutnya.
      picu('kembali aktif', abaikanJeda: true);
    } else {
      // Timer yang tetap hidup di latar belakang hanya menghabiskan baterai;
      // Android pun akan menahannya.
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Panggil saat keranjang baru saja dikosongkan (checkout selesai atau
  /// dibatalkan), untuk melunasi sinkron yang tadi ditunda.
  void lanjutkanYangTertunda() {
    if (!_tertunda) return;
    _tertunda = false;
    picu('keranjang kosong', abaikanJeda: true);
  }

  /// Alasan kenapa sinkron kali ini dilewati, atau null kalau boleh jalan.
  ///
  /// Dipisah dari [picu] supaya keputusannya bisa diuji tanpa jaringan.
  @visibleForTesting
  String? alasanDilewati({required DateTime sekarang, bool abaikanJeda = false}) {
    if (sedangMenyusunPesanan) return 'keranjang sedang berisi';
    if (SyncService.instance.sedangJalan) return 'sudah ada yang berjalan';
    if (!abaikanJeda &&
        _percobaanTerakhir != null &&
        sekarang.difference(_percobaanTerakhir!) < jedaMinimum) {
      return 'baru saja sinkron';
    }
    return null;
  }

  /// Jalankan sinkron kalau keadaannya memungkinkan.
  ///
  /// SENGAJA tanpa popup dan tanpa pesan apa pun. Popup kemajuan itu untuk
  /// sinkron yang DIMINTA pengguna; memunculkannya sendiri setiap lima menit
  /// akan menghalangi layar di tengah pekerjaan. Kegagalan juga didiamkan —
  /// transaksinya tetap tersimpan dan terkirim saat jaringan pulih, dan label
  /// "terakhir disinkronkan" sudah membuat kebasiannya terlihat.
  Future<void> picu(String alasan, {bool abaikanJeda = false}) async {
    final dilewati =
        alasanDilewati(sekarang: DateTime.now(), abaikanJeda: abaikanJeda);
    if (dilewati != null) {
      if (sedangMenyusunPesanan) _tertunda = true;
      return;
    }
    _percobaanTerakhir = DateTime.now();
    await SyncService.instance.jalankan();
  }

  @visibleForTesting
  void resetUntukTest() {
    _timer?.cancel();
    _timer = null;
    _percobaanTerakhir = null;
    _tertunda = false;
    sedangMenyusunPesanan = false;
  }
}
