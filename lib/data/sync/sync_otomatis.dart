import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

import 'package:flutter/widgets.dart';

import '../db.dart';
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

  /// Jeda sepi sebelum perubahan lokal dikirim.
  ///
  /// Perubahan tidak dikirim seketika, melainkan menunggu sesaat dan mengulang
  /// hitungan setiap ada perubahan baru. Menghapus lima produk beruntun jadi
  /// SATU perjalanan, bukan lima — dan satu perjalanan itu membawa semua baris
  /// yang tertunda, jadi tidak ada yang tertinggal.
  ///
  /// Sengaja sependek ini: HP lain yang menyegarkan beberapa detik kemudian
  /// harus sudah melihat perubahannya, kalau tidak seluruh gunanya hilang.
  static const jedaGabung = Duration(seconds: 3);

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

  /// True selagi form produk terbuka.
  ///
  /// Alasannya sama dengan keranjang — ada pekerjaan setengah jadi yang belum
  /// tercatat di database — tapi yang dipertaruhkan berbeda: berkas foto yang
  /// baru dipilih belum dirujuk baris mana pun, dan sinkron gambar membuang
  /// berkas semacam itu.
  bool sedangMenyuntingProduk = false;

  /// Ada pekerjaan yang tidak boleh diganggu sinkron.
  bool get _adaPekerjaanRawan =>
      sedangMenyusunPesanan || sedangMenyuntingProduk;

  Timer? _penggabung;
  StreamSubscription<void>? _pendengarTulisan;

  /// Diganti test untuk mengamati penjadwalan tanpa menyentuh jaringan.
  @visibleForTesting
  Future<void> Function(String alasan)? penggantiPicuUntukTest;

  /// Ada tulisan lokal — jadwalkan pengiriman setelah [jedaGabung] sepi.
  ///
  /// Perangkat yang MENGUBAH data yang mengirimkannya; perangkat yang ingin
  /// tahu cukup menyegarkan. Sebelum ini keduanya harus menyegarkan, sehingga
  /// pemilik yang baru menghapus produk masih harus menarik layarnya sendiri
  /// hanya supaya penghapusan itu naik ke server.
  void adaPerubahanLokal() {
    _penggabung?.cancel();
    _penggabung = Timer(jedaGabung, () {
      final kirim =
          penggantiPicuUntukTest ?? (a) => picu(a, abaikanJeda: true);
      kirim('perubahan lokal');
    });
  }

  /// Bolehkah tulisan yang baru terjadi ditanggapi?
  ///
  /// Dua penjaga, dan keduanya mencegah lingkaran yang sama — sinkron memicu
  /// dirinya sendiri: tarik, tulis, picu, tarik, tanpa henti.
  ///
  /// 1. Selagi sinkron berjalan, semua tulisan diabaikan; tulisan itu hampir
  ///    pasti berasal dari sinkron yang sedang menyimpan data server.
  ///
  /// 2. Tulisan yang HANYA menyentuh `sync_state` diabaikan juga. Tabel itu
  ///    murni lokal — berisi penanda waktu sinkron — dan ditulis pada SETIAP
  ///    putaran, termasuk putaran yang tidak menemukan apa-apa. Tanpa aturan
  ///    kedua ini, penjaga pertama masih bisa lolos: kabar tulisan tiba lewat
  ///    antrean, jadi bisa sampai sepersekian detik SETELAH sinkronnya selesai
  ///    dan penandanya sudah mati.
  ///
  /// Harga penjaga pertama: tulisan pengguna yang jatuh TEPAT saat sinkron
  /// berjalan ikut terlewat. Itu disengaja dan tidak berbahaya — barisnya tetap
  /// `pending`, lalu ikut terkirim pada perubahan berikutnya atau pada putaran
  /// berkala. Menebak-nebak asal tulisan lebih berisiko daripada menunggu.
  @visibleForTesting
  bool perluKirimSetelahTulisan({
    required Set<String> tabel,
    required bool sinkronSedangJalan,
  }) {
    if (sinkronSedangJalan) return false;
    return tabel.any((t) => t != _tabelPenandaSinkron);
  }

  static const _tabelPenandaSinkron = 'sync_state';

  void mulai() {
    WidgetsBinding.instance.addObserver(this);
    _nyalakanTimer();

    // Satu pendengar untuk SEMUA tulisan, bukan satu pemicu di tiap tempat
    // yang menulis. Ada dua puluh tempat semacam itu hari ini, dan setiap
    // fitur baru menambah satu lagi — cepat atau lambat ada yang terlewat.
    //
    // Sengaja MENDENGARKAN SEMUA TABEL, bukan daftar tabel yang disinkronkan.
    // Daftar semacam itu pasti ketinggalan begitu ada tabel baru. Dua tabel
    // yang tidak ikut sinkron pun tidak merepotkan: `sync_state` hanya ditulis
    // saat sinkron berjalan (sudah dijaga di bawah), dan katalog `permissions`
    // hanya ditulis sekali saat penyiapan.
    _pendengarTulisan?.cancel();
    _pendengarTulisan = db.tableUpdates(const TableUpdateQuery.any()).listen((
      perubahan,
    ) {
      if (!perluKirimSetelahTulisan(
        tabel: perubahan.map((p) => p.table).toSet(),
        sinkronSedangJalan: SyncService.instance.sedangJalan,
      )) {
        return;
      }
      adaPerubahanLokal();
    });
  }

  @visibleForTesting
  void berhenti() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _penggabung?.cancel();
    _penggabung = null;
    _pendengarTulisan?.cancel();
    _pendengarTulisan = null;
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

  /// Panggil saat pekerjaan yang menahan sinkron selesai — keranjang
  /// dikosongkan, atau form produk ditutup — untuk melunasi sinkron yang tadi
  /// ditunda.
  void lanjutkanYangTertunda() {
    if (!_tertunda) return;
    _tertunda = false;
    picu('pekerjaan rawan selesai', abaikanJeda: true);
  }

  /// Alasan kenapa sinkron kali ini dilewati, atau null kalau boleh jalan.
  ///
  /// Dipisah dari [picu] supaya keputusannya bisa diuji tanpa jaringan.
  @visibleForTesting
  String? alasanDilewati({required DateTime sekarang, bool abaikanJeda = false}) {
    if (sedangMenyusunPesanan) return 'keranjang sedang berisi';
    if (sedangMenyuntingProduk) return 'form produk sedang terbuka';
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
      if (_adaPekerjaanRawan) _tertunda = true;
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
    sedangMenyuntingProduk = false;
    _penggabung?.cancel();
    _penggabung = null;
    penggantiPicuUntukTest = null;
  }
}
