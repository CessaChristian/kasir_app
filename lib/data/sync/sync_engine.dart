import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import '../app_database.dart';
import 'kemajuan_sync.dart';
import '../supabase/supabase_service.dart';

/// Hasil satu putaran sinkronisasi.
class HasilSync {
  /// Baris yang DITERIMA dari server.
  ///
  /// Sengaja dipisah dari [berubah]: server mengirim setiap baris yang lebih
  /// baru dari penanda kita, dan sebagian di antaranya ternyata sudah sama
  /// persis dengan yang ada di sini. Melaporkan angka ini ke pengguna sebagai
  /// "data diperbarui" adalah kebohongan kecil yang bikin bingung — mereka
  /// menekan segarkan pada daftar yang tidak berubah, lalu diberi tahu ada
  /// belasan data baru.
  final int diperiksa;

  /// Baris yang BENAR-BENAR mengubah isi database lokal: baris baru, atau
  /// baris yang versinya di server lebih baru. Ini yang layak ditampilkan.
  final int berubah;

  final int didorong;

  /// Berkas gambar yang berpindah. Dipisah dari [berubah] karena sinkron
  /// gambar berjalan sebagai tahap tersendiri dan boleh gagal sendirian.
  final int gambarNaik;
  final int gambarTurun;
  final int gambarDihapus;
  final int gambarDihapusLokal;

  /// Kegagalan sinkron BARIS. Kegagalan gambar tidak ditaruh di sini supaya
  /// gambar yang gagal berpindah tidak membuat seluruh putaran dianggap gagal
  /// — transaksinya sendiri sudah aman terkirim.
  final String? error;

  /// Kegagalan sinkron GAMBAR, kalau ada.
  final String? errorGambar;

  /// Kenapa putaran ini tidak bisa menyambung sama sekali, atau null kalau
  /// sempat tersambung.
  ///
  /// [error] untuk log; ini untuk layar. Dipisah supaya layar tidak perlu
  /// menebak dari isi teks galat — tebakan seperti itu diam-diam rusak
  /// begitu kalimat galatnya diubah.
  final SebabTerputus? sebabTerputus;

  /// Semua tabel selesai DITARIK tanpa galat. Baris yang tertahan tidak
  /// menggagalkan tarikan, jadi dihitung terpisah sebelum dilaporkan ke
  /// server sebagai "tarikan bersih" (supabase/perangkat_tarik.sql).
  ///
  /// Dipisah dari [berhasil]: kiriman yang gagal tidak menghalangi HP ini
  /// menerima kabar dari server.
  final bool tarikSelesai;

  const HasilSync({
    this.diperiksa = 0,
    this.berubah = 0,
    this.didorong = 0,
    this.gambarNaik = 0,
    this.gambarTurun = 0,
    this.gambarDihapus = 0,
    this.gambarDihapusLokal = 0,
    this.error,
    this.errorGambar,
    this.sebabTerputus,
    this.tarikSelesai = false,
  });

  bool get berhasil => error == null;

  /// Salin hasil ini sambil menambahkan hasil tahap gambar.
  HasilSync denganGambar({
    int naik = 0,
    int turun = 0,
    int hapus = 0,
    int hapusLokal = 0,
    String? error,
  }) =>
      HasilSync(
        diperiksa: diperiksa,
        berubah: berubah,
        didorong: didorong,
        gambarNaik: naik,
        gambarTurun: turun,
        gambarDihapus: hapus,
        gambarDihapusLokal: hapusLokal,
        error: this.error,
        errorGambar: error,
        sebabTerputus: sebabTerputus,
        tarikSelesai: tarikSelesai,
      );

  /// Ada yang berhasil walau ada juga yang gagal.
  ///
  /// Dulu tidak ada keadaan ini: satu kegagalan membatalkan seluruh putaran,
  /// jadi hasilnya hanya "berhasil semua" atau "gagal semua". Sekarang tabel
  /// yang sehat tetap terkirim, dan pengguna berhak diberi tahu yang mana
  /// yang tidak.
  bool get sebagian => !berhasil && (berubah > 0 || didorong > 0);

  @override
  String toString() {
    if (!berhasil) {
      final n = berubah + didorong;
      return n > 0 ? 'SEBAGIAN ($n lolos): $error' : 'GAGAL: $error';
    }
    final g = errorGambar != null
        ? ', gambar GAGAL: $errorGambar'
        : (gambarNaik > 0 ||
                gambarTurun > 0 ||
                gambarDihapus > 0 ||
                gambarDihapusLokal > 0)
            ? ', gambar naik $gambarNaik turun $gambarTurun '
                'hapus $gambarDihapus server / $gambarDihapusLokal lokal'
            : '';
    return 'periksa $diperiksa, ubah $berubah, kirim $didorong$g';
  }
}

/// Dorongan satu tabel yang lolos sebagian.
///
/// Membawa jumlah yang BERHASIL terkirim, supaya baris sehat tetap terhitung
/// walau ada baris beracun di tabel yang sama.
class _GagalSebagian implements Exception {
  final String tabel;
  final int terkirim;
  final Object penyebab;

  _GagalSebagian(this.tabel, this.terkirim, this.penyebab);

  @override
  String toString() => penyebab.toString();
}

/// Satu tabel yang ikut disinkronkan.
///
/// Dibuat sebagai deskripsi, bukan kode terpisah per tabel, supaya menambah
/// tabel baru cukup menambah satu entri — bukan menyalin sepasang fungsi
/// dorong/tarik yang gampang beda halus satu sama lain.
class _Entitas {
  /// Nama tabel di PostgreSQL, sekaligus di SQLite.
  final String nama;

  /// Baris lokal yang belum terkirim, sudah diubah jadi bentuk JSON server.
  final Future<List<Map<String, dynamic>>> Function() ambilTertunda;

  /// Tulis satu baris dari server ke database lokal, TANPA pertimbangan
  /// apa pun.
  ///
  /// Keputusan boleh-tidaknya menulis sengaja TIDAK ditaruh di sini,
  /// melainkan terpusat di [SyncEngine._tarik]. Kalau setiap tabel memutuskan
  /// sendiri, tujuh salinan aturan yang sama akan berbeda halus satu sama
  /// lain — dan aturan inilah yang menentukan data pengguna hilang atau
  /// selamat.
  final Future<void> Function(Map<String, dynamic>) tulis;

  /// Tandai baris-baris ini sudah terkirim.
  final Future<void> Function(List<String>) tandaiTerkirim;

  const _Entitas({
    required this.nama,
    required this.ambilTertunda,
    required this.tulis,
    required this.tandaiTerkirim,
  });
}

/// Menyinkronkan database lokal dengan Supabase.
///
/// ── KENAPA TIDAK ADA TABEL OUTBOX TERPISAH ──
///
/// Kolom `sync_status` yang sudah ada DI SETIAP BARIS sudah berperan sebagai
/// antrean: baris bernilai 'pending' adalah baris yang belum terkirim.
///
/// Alternatifnya tabel antrean yang mencatat setiap operasi. Itu lebih setia
/// pada urutan kejadian, tapi tidak berguna di sini: penyelesaian konflik
/// memakai "yang terbaru menang". Kalau satu baris diubah tiga kali saat
/// offline, mengirim keadaan TERAKHIRNYA sekali menghasilkan yang sama
/// persis dengan memutar ulang tiga operasi — dengan sepertiga lalu lintas
/// dan tanpa tabel tambahan yang harus dijaga konsistensinya.
///
/// ── KENAPA PENGHAPUSAN TETAP TERKIRIM ──
///
/// Semua penghapusan bersifat lunak (`deleted_at` diisi, barisnya tetap
/// ada), jadi penghapusan terkirim sebagai perubahan biasa. Baris yang
/// benar-benar lenyap tidak bisa diberitahukan ke perangkat lain — server
/// hanya melihat ketiadaan, dan ketiadaan tidak bisa dikirim.
/// Baris terakhir sebuah halaman tarikan: capnya dan id-nya. Halaman
/// berikutnya mulai SESUDAH pasangan ini.
typedef PenandaHalaman = ({String nilai, String id});

class SyncEngine {
  final AppDatabase _db;

  /// Dipanggil setiap kali ada kemajuan, supaya lapisan tampilan bisa
  /// menunjukkan apa yang sedang terjadi. Boleh null di test.
  final void Function(KemajuanSync)? onKemajuan;

  SyncEngine(this._db, {this.onKemajuan});

  SupabaseService get _supabase => SupabaseService.instance;

  /// Pintu masuk untuk test: klien sungguhan yang mengarah ke server palsu,
  /// supaya test bisa memeriksa PERMINTAAN yang benar-benar dikirim —
  /// arah urutan dan filternya — bukan cuma hasil olahan server palsu.
  @visibleForTesting
  SupabaseClient? klienUntukTest;

  /// URUTAN PENTING — induk sebelum anak.
  ///
  /// Server menegakkan foreign key. Mengirim transaksi sebelum shift-nya ada
  /// akan ditolak, dan mengirim item sebelum transaksinya ada juga. Urutan
  /// yang sama dipakai saat menarik, dengan alasan yang sama.
  late final List<_Entitas> _entitas = [
    _users(),
    _userPermissions(),
    _categories(),
    _products(),
    _shifts(),
    _transactions(),
    _transactionItems(),
    _expenses(),
    // Paling akhir: menunjuk shift, akun, dan transaksi.
    _openBills(),
  ];

  Future<HasilSync> jalankan() async {
    if (!_supabase.online) {
      return const HasilSync(error: 'offline atau perangkat belum didaftarkan');
    }
    var diperiksa = 0;
    var berubah = 0;
    var didorong = 0;
    final gagal = <String>[];

    // ── TARIK ──
    //
    // Berhenti di kegagalan PERTAMA, dan itu disengaja. Urutannya induk
    // sebelum anak karena foreign key ditegakkan di database LOKAL: menulis
    // `transaction_items` setelah `products` gagal ditarik akan melanggar FK
    // dan menggagalkan barisnya satu per satu dengan pesan yang tidak ada
    // hubungannya dengan penyebab sebenarnya.
    //
    // Tarik dulu semuanya, baru dorong. Mendorong lebih dulu bisa menimpa
    // perubahan server yang belum sempat dilihat perangkat ini.
    var tarikSelesai = false;
    try {
      for (var i = 0; i < _entitas.length; i++) {
        final h = await _tarik(_entitas[i], i + 1);
        diperiksa += h.$1;
        berubah += h.$2;
      }
      tarikSelesai = true;
    } catch (e) {
      gagal.add('tarik: $e');
    }

    // ── DORONG ──
    //
    // Dijalankan MESKIPUN tarikan gagal. Ini pembalikan yang disengaja dari
    // perilaku lama, dan alasannya soal apa yang bisa hilang: data server yang
    // belum terbaca masih aman tersimpan di server, sedangkan transaksi yang
    // belum terkirim HANYA ada di HP ini. Membatalkan pengiriman gara-gara
    // pembacaan gagal berarti mempertaruhkan yang tidak punya salinan demi
    // yang punya.
    //
    // Per tabel pula: tidak ada alasan `expenses` ikut mati karena `shifts`
    // bermasalah. Anak yang gagal karena induknya belum naik pun tidak apa —
    // barisnya tetap `pending` dan ikut lagi di putaran berikutnya.
    final h = await _dorongSemua();
    didorong += h.$1;
    gagal.addAll(h.$2);

    return HasilSync(
      diperiksa: diperiksa,
      berubah: berubah,
      didorong: didorong,
      error: gagal.isEmpty ? null : gagal.join(' | '),
      tarikSelesai: tarikSelesai,
    );
  }

  void _lapor(String tahap, String entitas, int urutan, int baris, int total,
      {int perubahan = 0}) {
    onKemajuan?.call(KemajuanSync(
      tahap: tahap,
      entitas: entitas,
      entitasKe: urutan,
      // Termasuk tahap gambar yang dikerjakan SyncGambar setelah ini. Kalau
      // dihitung 7 di sini lalu 8 di sana, bilah kemajuannya melompat mundur.
      totalEntitas: KemajuanSync.totalTahap,
      baris: baris,
      totalBaris: total,
      perubahan: perubahan,
    ));
  }

  // ------------------------------------------------------------------
  // TARIK / DORONG
  // ------------------------------------------------------------------

  /// Menarik satu tabel. Mengembalikan (baris diterima, baris benar-benar
  /// berubah).
  ///
  /// ── KENAPA VERSI SERVER TIDAK LANGSUNG DITIMPAKAN ──
  ///
  /// Sebelumnya baris server ditulis begitu saja lewat `insertOnConflictUpdate`
  /// tanpa membandingkan apa pun, sekaligus menyetel `sync_status = 'synced'`.
  /// Untuk baris yang punya perubahan lokal belum terkirim, akibatnya fatal
  /// dan senyap:
  ///
  /// ```
  /// 1. pengguna menambah gambar   -> lokal: image_path terisi, 'pending'
  /// 2. pengguna menyegarkan       -> TARIK dulu, baru DORONG
  /// 3. tarikan menimpa baris itu  -> image_path kembali NULL, jadi 'synced'
  /// 4. giliran dorong             -> tidak ada lagi yang 'pending'
  /// ```
  ///
  /// Gambarnya hilang dari layar DAN tidak pernah sampai ke server. Filenya
  /// tetap ada di disk tanpa ada yang menunjuknya.
  ///
  /// ── ATURANNYA MURNI PERBANDINGAN WAKTU ──
  ///
  /// | keadaan                        | tindakan                            |
  /// |--------------------------------|-------------------------------------|
  /// | belum ada barisnya di sini     | tulis — ini data baru               |
  /// | server lebih baru              | tulis — termasuk kalau isinya hapus |
  /// | waktunya sama persis           | lewati — versinya memang sama       |
  /// | lokal lebih baru               | lewati — jangan mundur              |
  ///
  /// Status `pending` sengaja TIDAK ikut jadi syarat, karena aturan waktu di
  /// atas sudah menanganinya sendiri: baris `pending` yang lebih baru akan
  /// dilewati sehingga statusnya tetap `pending` dan ikut terdorong di tahap
  /// berikutnya. Sebaliknya, penghapusan dari server yang lebih baru tetap
  /// menang — jadi produk yang dihapus pemilik tidak hidup lagi di HP kasir.
  ///
  /// Kasus seri (`waktunya sama persis`) memenangkan yang lokal. `updated_at`
  /// lokal beresolusi DETIK, jadi dua perubahan dalam detik yang sama tidak
  /// bisa dibedakan urutannya. Kalau ragu, yang belum terkirim lebih layak
  /// diselamatkan: ia hanya ada di perangkat ini, sedangkan versi server
  /// masih tersimpan di server dan bisa dikirim ulang.
  /// Kolom URUTAN KEDATANGAN di server, diisi trigger, tidak bisa disetel
  /// perangkat. Lihat `supabase/sync_urutan.sql`.
  static const kolomUrut = 'server_urut';

  /// Berapa jauh ke belakang tarikan mengulang dari penandanya.
  ///
  /// Stempel `server_urut` diberikan saat baris DITULIS, sedangkan barisnya
  /// baru terlihat pembaca lain saat transaksinya COMMIT. Dua pengiriman yang
  /// bersamaan bisa commit tidak sesuai urutan stempelnya: yang berstempel
  /// lebih tua justru muncul belakangan. Tanpa jeda ini, baris seperti itu
  /// terlewat permanen — persis kebocoran yang mau ditutup.
  ///
  /// Mengulang tidak merugikan: menggabungkan bersifat idempoten, baris yang
  /// isinya sama dilewati. Satu menit jauh lebih lama dari umur transaksi
  /// PostgREST mana pun, dan pada 500 transaksi/hari isinya nyaris nol baris.
  static const jedaAman = Duration(minutes: 1);

  /// Satu halaman tarikan. PostgREST memotong hasil di batas barisnya sendiri
  /// (bawaan Supabase 1000) TANPA memberi tahu, jadi halamannya diminta
  /// eksplisit dan diulang sampai habis.
  static const ukuranHalaman = 500;

  /// Pintu masuk untuk test: menggantikan permintaan ke server.
  ///
  /// Menerima kolom dan penanda yang BENAR-BENAR dipakai kueri, supaya test
  /// bisa membuktikan enginenya menyaring pada kolom yang tepat — bukan
  /// sekadar memercayai bahwa ia melakukannya.
  ///
  /// [sejak] hanya dipakai halaman pertama (`kolom >= sejak`). Halaman
  /// berikutnya memakai [setelah]: baris yang urutan `(kolom, id)`-nya
  /// sesudah baris terakhir halaman sebelumnya.
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(
    String tabel,
    String kolom,
    String? sejak,
    PenandaHalaman? setelah,
    int batas,
  )? penarikUntukTest;

  Future<(int, int)> _tarik(_Entitas e, int urutan) async {
    final hasil = await _tarikTabelIni(e, urutan);
    final ulang = await _cobaLagiTertahan(e, urutan);
    return (hasil.$1 + ulang.$1, hasil.$2 + ulang.$2);
  }

  Future<(int, int)> _tarikTabelIni(_Entitas e, int urutan) async {
    final sejak = await _kursorTarikTerakhir(e.nama);

    try {
      return await _tarikBertahap(e, urutan, _mundurkan(sejak), true);
    } on PostgrestException catch (err) {
      if (err.code != '42703') rethrow;

      // Servernya belum dimigrasi — `supabase/sync_urutan.sql` belum
      // dijalankan. Aplikasi TIDAK boleh ikut mati karenanya: pembaruan
      // aplikasi bisa sampai ke HP sebelum perubahan databasenya dijalankan,
      // dan warung yang berhenti bisa menerima uang jauh lebih mahal daripada
      // sinkron yang boros.
      //
      // Seluruh tabel ditarik dan penandanya sengaja TIDAK disimpan. Itu
      // memang boros, tapi tidak bisa kehilangan baris — dan keadaannya
      // sementara sampai SQL-nya dijalankan.
      debugPrint('[sync] ${e.nama}: kolom $kolomUrut belum ada di server. '
          'Jalankan supabase/sync_urutan.sql. Sementara ini SELURUH tabel '
          'ditarik tiap sinkron.');
      return _tarikBertahap(e, urutan, null, false);
    }
  }

  /// Menarik halaman demi halaman sampai habis.
  ///
  /// ── KENAPA BUKAN NOMOR HALAMAN (offset) ──
  ///
  /// Halaman ditandai NILAI baris terakhir, bukan posisinya. Dengan offset,
  /// baris yang DIUBAH di server selagi kita menarik akan pindah ke ujung
  /// urutan, dan semua baris sesudahnya bergeser maju satu — sehingga baris
  /// yang tadinya tepat di awal halaman berikutnya terlewati, permanen.
  ///
  /// Itu justru terjadi saat datanya paling banyak: tarikan pertama sesudah
  /// perangkat lama tidak sinkron, ketika halamannya memang lebih dari satu.
  ///
  /// Nilai tidak bisa bergeser seperti itu: baris yang diubah pindah ke
  /// belakang batas yang sedang kita pegang, jadi ia tetap ikut tertarik.
  ///
  /// ── KENAPA PENANDANYA PASANGAN (cap, id), BUKAN CAP SAJA ──
  ///
  /// Banyak baris bisa punya cap yang PERSIS sama — misalnya ratusan item
  /// struk yang diunggah dalam satu kiriman. Dengan cap saja, halaman
  /// berikutnya mulai lagi dari cap yang sama dan mendapat 500 baris yang
  /// sama persis; tarikannya macet di situ, dan sisa gumpalan beserta SEMUA
  /// baris sesudahnya tidak pernah tertarik. Ini benar-benar terjadi: HP
  /// yang dipasang dari nol kehilangan 109 item struk, tanpa pesan apa pun.
  ///
  /// `id` itu unik, jadi pasangan (cap, id) selalu maju — sebesar apa pun
  /// gumpalan bercap sama.
  Future<(int, int)> _tarikBertahap(
    _Entitas e,
    int urutan,
    String? sejak,
    bool pakaiUrut,
  ) async {
    final kolom = pakaiUrut ? kolomUrut : 'updated_at';
    PenandaHalaman? setelah;
    var diterima = 0;
    var berubah = 0;

    // Batas putaran sebagai jaring pengaman: kalaupun suatu hari ada keadaan
    // yang membuat penandanya tidak maju, sinkronnya berhenti alih-alih
    // berputar selamanya.
    for (var putaran = 0; putaran < 1000; putaran++) {
      final halaman = await _halaman(e.nama, sejak, setelah, pakaiUrut);
      if (halaman.isEmpty) break;

      // Ditulis per halaman, dan penandanya disimpan sesudah tiap halaman.
      // Dulu semua halaman ditampung di memori lebih dulu: HP yang baru
      // dipasang setelah setahun menampung ratusan ribu baris sekaligus,
      // dan putus di tengah jalan berarti mulai lagi dari nol.
      //
      // Baris yang PINDAH ke belakang selagi kita menarik (diubah di server)
      // bisa datang dua kali. Keduanya digabung biasa: salinan kedua lebih
      // baru dan menang, salinan yang sama persis dilewati. Dulu id semua
      // baris disimpan di memori untuk membuang salinan kedua — HP baru
      // menampung ratusan ribu id, dan justru versi TERBARU yang dibuang.
      final h = await _gabungkan(e, halaman, urutan);
      diterima += h.$1;
      berubah += h.$2;

      if (halaman.length < ukuranHalaman) break;
      final akhir = halaman.last;
      final nilai = akhir[kolom];
      if (nilai is! String) break;
      setelah = (nilai: nilai, id: akhir['id'] as String);
    }

    return (diterima, berubah);
  }

  /// Satu halaman baris dari server, terurut menurut kedatangannya.
  Future<List<Map<String, dynamic>>> _halaman(
    String tabel,
    String? sejak,
    PenandaHalaman? setelah,
    bool pakaiUrut,
  ) async {
    // Urutannya tetap dibutuhkan walau kolom urutan belum ada: menarik
    // bertahap tanpa urutan yang pasti bisa melewatkan baris antar halaman.
    final kolom = pakaiUrut ? kolomUrut : 'updated_at';

    final pengganti = penarikUntukTest;
    if (pengganti != null) {
      return pengganti(tabel, kolom, sejak, setelah, ukuranHalaman);
    }

    var query = (klienUntukTest ?? _supabase.client!).from(tabel).select();
    if (setelah != null) {
      // "Sesudah baris terakhir": capnya lebih besar, ATAU capnya sama tapi
      // id-nya lebih besar. Capnya dijadikan UTC berakhiran Z dan diapit
      // kutip — titik dua, titik, dan tanda plus punya arti sendiri di
      // dalam filter `or` PostgREST.
      final v = DateTime.parse(setelah.nilai).toUtc().toIso8601String();
      query = query.or('$kolom.gt."$v",'
          'and($kolom.eq."$v",id.gt."${setelah.id}")');
    } else if (sejak != null) {
      // `gte`, bukan `gt`: stempel kembar tidak boleh membuat baris terlewat.
      // Barisnya yang persis di batas ikut tertarik lagi, dan itu murah —
      // menggabungkannya tidak mengubah apa pun.
      query = query.gte(kolom, sejak);
    }
    // `ascending: true` WAJIB ditulis: bawaan `order()` di pustaka ini
    // justru TURUN. Dulu tidak ditulis, dan tarikan yang lebih dari satu
    // halaman cuma mendapat 500 baris TERBARU — sisanya tidak pernah sampai.
    return query
        .order(kolom, ascending: true)
        .order('id', ascending: true)
        .limit(ukuranHalaman);
  }

  /// Tulis satu baris server. Kalau database HP ini menolaknya — aturan
  /// isian yang belum mengenal nilai baru, relasi yang induknya belum ada —
  /// barisnya DISISIHKAN ke `baris_tertahan` dan tarikan jalan terus.
  /// True kalau tertulis.
  ///
  /// Dulu galatnya menghentikan seluruh tarikan, dan penandanya tidak pernah
  /// maju. Satu baris bermasalah membuat HP mengunduh ulang semua baris sejak
  /// hari itu setiap lima menit, dan tabel sesudahnya tidak pernah ditarik.
  Future<bool> _tulisAtauTahan(_Entitas e, Map<String, dynamic> r) async {
    final id = r['id'] as String;
    final tertahan = await _idTertahan(e.nama);
    try {
      await e.tulis(r);
    } catch (err) {
      debugPrint('[sync] ${e.nama}/$id ditahan: $err');
      await _db.into(_db.barisTertahan).insertOnConflictUpdate(
            BarisTertahanCompanion(
              entity: Value(e.nama),
              rowId: Value(id),
              alasan: Value('$err'),
            ),
          );
      tertahan.add(id);
      return false;
    }
    if (tertahan.contains(id)) await _lepasTahanan(e.nama, id);
    return true;
  }

  /// Id baris tertahan per tabel, dibaca sekali per putaran — supaya baris
  /// yang lolos tidak perlu satu kueri tambahan masing-masing.
  final _cacheTertahan = <String, Set<String>>{};

  Future<Set<String>> _idTertahan(String tabel) async =>
      _cacheTertahan[tabel] ??= {
        for (final t in await (_db.select(_db.barisTertahan)
              ..where((t) => t.entity.equals(tabel)))
            .get())
          t.rowId,
      };

  Future<void> _lepasTahanan(String tabel, String id) async {
    _cacheTertahan[tabel]?.remove(id);
    await (_db.delete(_db.barisTertahan)
          ..where((t) => t.entity.equals(tabel) & t.rowId.equals(id)))
        .go();
  }

  /// Ambil ulang baris tertahan tabel [e] dari server, lalu coba simpan
  /// lagi — misalnya setelah aplikasinya diperbarui, atau induknya sudah
  /// tiba. Baris yang sudah tidak ada di server dilepas dari daftar.
  /// Mengembalikan (baris diterima, baris berubah).
  Future<(int, int)> _cobaLagiTertahan(_Entitas e, int urutan) async {
    // Disalin: daftarnya berubah selagi baris dicoba.
    final tertahan = (await _idTertahan(e.nama)).toList();
    if (tertahan.isEmpty) return (0, 0);

    // Baris yang tertahan hampir selalu menunggu aplikasinya diperbarui,
    // jadi tidak perlu ditanyakan tiap lima menit. Penandanya di memori:
    // membuka aplikasi — termasuk sesudah diperbarui — selalu mencoba.
    final kini = DateTime.now();
    final terakhir = _cobaLagiTerakhir[e.nama];
    if (terakhir != null && kini.difference(terakhir) < jedaCobaLagi) {
      return (0, 0);
    }
    _cobaLagiTerakhir[e.nama] = kini;

    var diterima = 0;
    var berubah = 0;
    const potongan = 100;
    for (var i = 0; i < tertahan.length; i += potongan) {
      final ids = tertahan.skip(i).take(potongan).toList();
      final baris = await _ambilMenurutId(e.nama, ids);
      final ada = {for (final r in baris) r['id'] as String};
      for (final id in ids) {
        if (ada.contains(id)) continue;
        await _lepasTahanan(e.nama, id);
        // Sudah tidak ada di server = sudah DIBUANG buang sampah, dan yang
        // dibuang hanya produk/kategori yang terhapus. Salinan lama di HP
        // ini tidak boleh terus tampil (mungkin dengan harga lama).
        // Ditandai 'synced' supaya tidak dikirim balik dan hidup lagi.
        if (_sampahTakPerluDisimpan(e.nama)) {
          await _db.customUpdate(
            'UPDATE ${e.nama} SET deleted_at = ?, sync_status = \'synced\' '
            'WHERE id = ? AND deleted_at IS NULL',
            variables: [
              Variable.withDateTime(kini),
              Variable.withString(id),
            ],
          );
        }
      }
      for (final r in baris) {
        final id = r['id'] as String;
        final lokal = await _keadaanLokal(e.nama, id);
        if (lokal != null &&
            !_serverMenang(lokal, _mikro(r['updated_at'] as String))) {
          // Versi di HP sudah sama atau lebih baru: tidak ada yang tertahan.
          await _lepasTahanan(e.nama, id);
          continue;
        }
        diterima++;
        if (await _tulisAtauTahan(e, r)) berubah++;
      }
    }
    _lapor('menarik', e.nama, urutan, diterima, diterima, perubahan: berubah);
    return (diterima, berubah);
  }

  /// Seberapa sering baris tertahan ditanyakan ulang ke server.
  static const jedaCobaLagi = Duration(hours: 1);

  /// Kapan baris tertahan tiap tabel terakhir dicoba. Sengaja statis dan
  /// hanya di memori: satu mesin dibuat per putaran sinkron.
  static final _cobaLagiTerakhir = <String, DateTime>{};

  @visibleForTesting
  static void lupakanCobaLagi() => _cobaLagiTerakhir.clear();

  /// Pengganti pengambilan baris menurut id untuk test.
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(
    String tabel,
    List<String> ids,
  )? pengambilIdUntukTest;

  Future<List<Map<String, dynamic>>> _ambilMenurutId(
    String tabel,
    List<String> ids,
  ) {
    final pengganti = pengambilIdUntukTest;
    if (pengganti != null) return pengganti(tabel, ids);
    return (klienUntukTest ?? _supabase.client!)
        .from(tabel)
        .select()
        .inFilter('id', ids);
  }

  /// Penanda dimundurkan sejauh [jedaAman]. Null tetap null — artinya belum
  /// pernah menarik sama sekali, jadi ambil semuanya.
  static String? _mundurkan(String? sejak) {
    if (sejak == null) return null;
    final t = DateTime.tryParse(sejak);
    if (t == null) return sejak;
    return t.subtract(jedaAman).toUtc().toIso8601String();
  }

  /// Menggabungkan baris dari server ke database lokal, tanpa menyentuh
  /// jaringan.
  ///
  /// Dipisah dari [_tarik] supaya aturan menang-kalah di bawah bisa diuji
  /// melawan database sungguhan tanpa perlu server — aturan inilah yang
  /// menentukan perubahan pengguna selamat atau hilang, jadi ia layak diuji
  /// langsung, bukan lewat tiruan.
  Future<(int, int)> _gabungkan(
    _Entitas e,
    List<Map<String, dynamic>> baris,
    int urutan,
  ) async {
    _lapor('menarik', e.nama, urutan, 0, baris.length);
    if (baris.isEmpty) return (0, 0);

    String? kursorTertinggi;
    var tertinggi = -1 << 62;
    var sudah = 0;
    var berubah = 0;

    for (final r in baris) {
      final waktuServer = r['updated_at'] as String;
      final mikroServer = _mikro(waktuServer);
      final lokal = await _keadaanLokal(e.nama, r['id'] as String);
      final terhapusDiServer = r['deleted_at'] != null;

      if (lokal == null && terhapusDiServer && _sampahTakPerluDisimpan(e.nama)) {
        // Produk atau kategori yang belum pernah ada di sini dan datang sudah
        // terhapus: tidak disimpan sama sekali. Tidak ada yang bisa
        // merujuknya — item struk tidak terikat ke produk (v24), dan server
        // tidak lagi menyimpan produk aktif yang menunjuk kategori terhapus
        // (`supabase/kategori_terhapus.sql`). Penandanya tetap maju di bawah.
      } else if (lokal == null || _serverMenang(lokal, mikroServer)) {
        if (await _tulisAtauTahan(e, r)) {
          // Baris terhapus yang belum pernah ada di sini — transaksi dan
          // pengeluaran yang DIBATALKAN — tetap ditulis karena itu catatan,
          // tapi tidak terlihat sebagai "data diperbarui" bagi pemakai.
          if (lokal != null || !terhapusDiServer) berubah++;
        }
      }

      sudah++;
      // Dilaporkan berkala saja — memanggil setState seribu kali justru
      // membuat tampilan tersendat.
      if (sudah % 25 == 0 || sudah == baris.length) {
        _lapor('menarik', e.nama, urutan, sudah, baris.length,
            perubahan: berubah);
      }

      // Penandanya mengikuti URUTAN KEDATANGAN, bukan `updated_at`. Dua
      // kolom itu memang berbeda tugas, dan memakai `updated_at` di sini
      // adalah sumber kebocoran yang ditutup `supabase/sync_urutan.sql`.
      //
      // Server yang belum dimigrasi tidak punya kolomnya. Dalam keadaan itu
      // penandanya sengaja TIDAK dimajukan: lebih baik menarik ulang tiap
      // kali daripada memajukannya dengan nilai yang salah arti dan
      // melewatkan baris diam-diam.
      final urut = r[kolomUrut];
      if (urut is String) {
        final mikroUrut = _mikro(urut);
        if (mikroUrut > tertinggi) {
          tertinggi = mikroUrut;
          kursorTertinggi = urut;
        }
      }
    }

    if (kursorTertinggi != null) {
      await _catatKursorTarik(e.nama, kursorTertinggi);
    }
    return (baris.length, berubah);
  }

  /// Tabel yang baris terhapusnya cuma sampah, bukan catatan. Transaksi dan
  /// pengeluaran yang terhapus adalah yang DIBATALKAN — bukti untuk owner —
  /// jadi selalu disimpan.
  static bool _sampahTakPerluDisimpan(String tabel) =>
      tabel == 'products' || tabel == 'categories';

  /// Menjalankan tarikan lengkap — termasuk penanda, jeda aman, dan paginasi
  /// — untuk SATU tabel saja.
  ///
  /// Dipakai saat login untuk menanyakan shift terbuka ke server sebelum
  /// memutuskan membuat yang baru, dan oleh test bersama [penarikUntukTest].
  Future<int> tarikTabel(String namaTabel) async {
    final (jumlah, _) =
        await _tarik(_entitas.firstWhere((e) => e.nama == namaTabel), 1);
    return jumlah;
  }

  /// Menarik SEMUA tabel, induk sebelum anak, TANPA mengirim apa pun.
  ///
  /// Untuk pemeriksaan cepat yang hanya butuh kabar terbaru (Open Bill:
  /// sebelum tutup shift, sesudah bayar/hapus ditolak). Menarik `open_bills`
  /// SAJA tidak cukup: bill yang dilunasi HP lain menunjuk transaksi yang
  /// belum ada di HP ini, foreign key lokal menolaknya, dan bill itu tetap
  /// terlihat terbuka. Tarikan bertahap hanya membawa baris yang berubah,
  /// jadi biasanya tetap ringan. Galat pertama menghentikan tarikan.
  Future<void> tarikSemua() async {
    for (var i = 0; i < _entitas.length; i++) {
      await _tarik(_entitas[i], i + 1);
    }
  }

  /// Pintu masuk untuk test: menggabungkan baris server ke tabel bernama
  /// [namaTabel]. Diperlukan karena `_Entitas` sengaja privat.
  @visibleForTesting
  Future<(int, int)> gabungkanTabel(
    String namaTabel,
    List<Map<String, dynamic>> baris,
  ) =>
      _gabungkan(_entitas.firstWhere((e) => e.nama == namaTabel), baris, 1);

  /// Keadaan baris lokal yang dipakai untuk memutuskan menang-kalah.
  ///
  /// Dibaca lewat SQL mentah karena berlaku untuk ketujuh tabel; menuliskan
  /// tujuh kueri drift yang identik hanya menambah tempat untuk salah ketik.
  /// Kolom `updated_at` berisi DETIK epoch (bawaan drift), dikalikan sejuta
  /// supaya sebanding dengan waktu server yang bermikrodetik.
  Future<({int mikro, bool pending})?> _keadaanLokal(
      String tabel, String id) async {
    final baris = await _db.customSelect(
      'SELECT updated_at, sync_status FROM $tabel WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (baris == null) return null;
    return (
      mikro: baris.read<int>('updated_at') * 1000000,
      pending: baris.read<String>('sync_status') == 'pending',
    );
  }

  /// Apakah versi server layak menimpa versi lokal.
  ///
  /// ── KENAPA BARIS `pending` DIBANDINGKAN PADA RESOLUSI DETIK ──
  ///
  /// Waktu lokal hanya beresolusi DETIK (bawaan drift), sedangkan server
  /// menyimpan MIKRODETIK. Begitu baris server disalin ke sini, pecahannya
  /// hilang — sehingga versi server selamanya terlihat "lebih baru" daripada
  /// salinan lokalnya sendiri:
  ///
  /// ```
  /// server : 10:04:11.430427
  /// lokal  : 10:04:11.000000   <- salinan baris yang SAMA, pecahan terbuang
  /// ```
  ///
  /// Untuk baris `pending` akibatnya fatal — pengguna yang mengedit pada detik
  /// yang sama dengan cap waktu server akan kehilangan editnya, padahal dalam
  /// kenyataan edit itu terjadi BELAKANGAN.
  ///
  /// ── KENAPA BARIS `synced` SEKARANG IKUT DIBANDINGKAN PER DETIK ──
  ///
  /// Dulu baris `synced` dibandingkan mikrodetik-lawan-detik, dengan alasan
  /// "paling-paling ditulis ulang dengan isi yang sama". Itu benar, tapi
  /// akibatnya baris yang cap servernya berpecahan DITULIS ULANG SELAMANYA —
  /// tiap sinkron, tanpa henti, karena salinan lokalnya tidak akan pernah bisa
  /// menyamai pecahan itu:
  ///
  /// ```
  /// server : 2026-09-03T07:19:37.57   ->  1788419977570000
  /// lokal  : 2026-09-03T07:19:37      ->  1788419977000000   selalu lebih kecil
  /// ```
  ///
  /// Selama penandanya `gt`, baris seperti itu tersaring keluar sesudah sekali
  /// tertarik, jadi tidak terlihat. Begitu penandanya memakai jeda aman,
  /// barisnya kembali masuk jangkauan tiap kali — dan pengguna melihat
  /// "2 data diperbarui" berulang padahal tidak ada yang berubah. Penunjuk
  /// yang berbohong seperti itu membuat orang berhenti mempercayainya, dan
  /// penunjuk yang diabaikan sama saja dengan tidak ada.
  ///
  /// Membandingkan per detik TIDAK mengubah apa pun untuk baris yang ditulis
  /// aplikasi: sisi lokal hanya punya detik, jadi yang didorong ke server pun
  /// selalu berpecahan nol. Yang berubah hanya baris yang cap waktunya
  /// diberikan server sendiri — dan untuk baris itu, perbedaan di bawah satu
  /// detik memang tidak bisa diamati dari sini.
  static bool _serverMenang(
      ({int mikro, bool pending}) lokal, int mikroServer) {
    const sejuta = 1000000;
    return (mikroServer ~/ sejuta) > (lokal.mikro ~/ sejuta);
  }

  /// Waktu ISO dari server jadi mikrodetik epoch, untuk dibandingkan.
  static int _mikro(String iso) =>
      DateTime.parse(iso).microsecondsSinceEpoch;

  /// Mendorong SEMUA tabel. Mengembalikan (jumlah terkirim, daftar gagal).
  ///
  /// Satu tabel yang gagal tidak menghentikan yang lain. Anak yang ditolak
  /// karena induknya belum naik pun tidak apa — barisnya tetap `pending` dan
  /// ikut lagi di putaran berikutnya.
  @visibleForTesting
  Future<(int, List<String>)> dorongSemua() => _dorongSemua();

  Future<(int, List<String>)> _dorongSemua() async {
    var didorong = 0;
    final gagal = <String>[];
    for (var i = 0; i < _entitas.length; i++) {
      try {
        didorong += await _dorong(_entitas[i], i + 1);
      } on _GagalSebagian catch (g) {
        didorong += g.terkirim;
        gagal.add('${g.tabel}: ${g.penyebab}');
      } catch (e) {
        gagal.add('${_entitas[i].nama}: $e');
      }
    }
    return (didorong, gagal);
  }

  Future<int> _dorong(_Entitas e, int urutan) async {
    final tertunda = await e.ambilTertunda();
    _lapor('mengirim', e.nama, urutan, 0, tertunda.length);
    if (tertunda.isEmpty) return 0;

    // Dikirim per potongan. Satu permintaan berisi ratusan baris gampang
    // melewati batas ukuran badan permintaan, dan kalau gagal seluruhnya
    // harus diulang dari nol.
    const ukuranPotongan = 100;
    final sampai = <Map<String, dynamic>>[];
    Object? galatTerakhir;

    for (var i = 0; i < tertunda.length; i += ukuranPotongan) {
      final potongan = tertunda.skip(i).take(ukuranPotongan).toList();
      try {
        await _kirim(e, potongan);
        sampai.addAll(potongan);
      } catch (_) {
        // Potongan ditolak. Bisa jadi SELURUH isinya bermasalah, tapi jauh
        // lebih sering cuma SATU baris — dan 99 baris sehat lainnya ikut
        // tertahan tanpa sebab.
        //
        // Ini bukan dugaan: pernah terjadi di project ini, 78 baris
        // berformat ID lama ditolak dengan
        // `invalid input syntax for type uuid`, dan tabelnya macet setiap
        // sync karena baris sehat di potongan yang sama tidak pernah lolos.
        //
        // Maka potongan yang gagal dipecah dan dicoba satu per satu. Hanya
        // berjalan saat gagal, jadi jalur normal tidak ikut melambat.
        final h = await _kirimSatuSatu(e, potongan);
        sampai.addAll(h.$1);
        galatTerakhir ??= h.$2;
      }
      _lapor('mengirim', e.nama, urutan,
          (i + potongan.length).clamp(0, tertunda.length), tertunda.length);
    }

    await _tandaiYangTidakBerubah(e, sampai);
    final terkirim = sampai.length;

    // Baris yang tetap ditolak SENGAJA dibiarkan `pending`, jadi ia dicoba
    // lagi di sinkronisasi berikutnya. Menyerah diam-diam pada data transaksi
    // jauh lebih berbahaya daripada berisik — dan biayanya terukur kecil:
    // satu permintaan ~266 byte per baris beracun per putaran, karena baris
    // sehat sudah lolos lewat percobaan satu per satu di atas.
    if (galatTerakhir != null) {
      throw _GagalSebagian(e.nama, terkirim, galatTerakhir);
    }
    return terkirim;
  }

  /// Pengganti pengirim untuk test.
  ///
  /// Perilaku yang paling penting di sini justru muncul saat GAGAL — baris
  /// beracun, tabel yang ditolak, potongan yang separuh lolos. Semuanya
  /// mustahil dipicu lewat server sungguhan tanpa merusak data, jadi jalur
  /// pengirimannya dibuat bisa diganti.
  @visibleForTesting
  Future<void> Function(String tabel, List<Map<String, dynamic>> baris)?
      pengirimUntukTest;

  Future<void> _kirim(_Entitas e, List<Map<String, dynamic>> baris) async {
    final pengganti = pengirimUntukTest;
    if (pengganti != null) {
      await pengganti(e.nama, baris);
    } else {
      await _supabase.client!.from(e.nama).upsert(baris);
    }
  }

  /// Cap "terkirim" HANYA untuk baris yang isinya di HP masih sama persis
  /// dengan yang tadi dikirim ([sampai]).
  ///
  /// Pengiriman makan waktu, dan kasir tetap bekerja selama itu. Contoh:
  /// transaksi Es Teh sedang dikirim, lalu kasir membatalkannya. Yang sampai
  /// di server versi SAH. Dulu barisnya tetap dicap terkirim berdasarkan
  /// id-nya saja — pembatalannya tidak pernah dikirim, dan HP lain serta
  /// laporan owner menghitung Es Teh itu selamanya. Baris yang berubah tetap
  /// `pending` dan ikut putaran berikutnya.
  ///
  /// Dibaca ulang dan dicap di dalam SATU transaksi database, jadi tidak ada
  /// tulisan yang bisa menyelip di antara mencocokkan dan mengecap.
  /// `updated_at` saja tidak cukup sebagai pembanding: nilainya per detik,
  /// dan sebagian kolom (mis. penghitung salah PIN) berubah tanpa
  /// menyentuhnya.
  Future<void> _tandaiYangTidakBerubah(
    _Entitas e,
    List<Map<String, dynamic>> sampai,
  ) async {
    if (sampai.isEmpty) return;
    await _db.transaction(() async {
      final kini = {
        for (final r in await e.ambilTertunda()) r['id'] as String: r,
      };
      await e.tandaiTerkirim([
        for (final r in sampai)
          if (_samaPersis(kini[r['id']], r)) r['id'] as String,
      ]);
    });
  }

  static bool _samaPersis(Map<String, dynamic>? a, Map<String, dynamic> b) =>
      a != null && jsonEncode(a) == jsonEncode(b);

  /// Mengembalikan (baris yang lolos, galat pertama yang ditemui).
  Future<(List<Map<String, dynamic>>, Object?)> _kirimSatuSatu(
    _Entitas e,
    List<Map<String, dynamic>> potongan,
  ) async {
    final lolos = <Map<String, dynamic>>[];
    Object? galat;
    for (final baris in potongan) {
      try {
        await _kirim(e, [baris]);
        lolos.add(baris);
      } catch (err) {
        galat ??= err;
      }
    }
    return (lolos, galat);
  }

  /// Tandai baris sudah terkirim.
  ///
  /// `updated_at` SENGAJA tidak ikut diubah. Kolom itu menyatakan kapan
  /// datanya berubah menurut pengguna, bukan kapan ia terkirim — dan
  /// nilainya dipakai untuk memutuskan versi mana yang menang. Menyentuhnya
  /// di sini akan membuat baris ini selalu "menang" atas perubahan perangkat
  /// lain tanpa alasan.
  Future<void> _tandai(String tabel, List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.customUpdate(
      "UPDATE $tabel SET sync_status = 'synced' "
      "WHERE id IN (${List.filled(ids.length, '?').join(',')})",
      variables: [for (final id in ids) Variable.withString(id)],
    );
  }

  // ------------------------------------------------------------------
  // Deskripsi tiap tabel
  // ------------------------------------------------------------------

  _Entitas _users() => _Entitas(
        nama: 'users',
        ambilTertunda: () async {
          final r = await (_db.select(_db.users)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final u in r)
              {
                'id': u.id,
                'username': u.username,
                // Hash PIN ikut terkirim supaya kasir bisa login dari
                // perangkat lain. Aman: PBKDF2 120.000 iterasi, dan RLS
                // menutup tabel ini dari akses tanpa login.
                'pin_hash': u.pinHash,
                'salt': u.salt,
                'role': u.role,
                'is_active': u.isActive,
                'recovery_hash': u.recoveryHash,
                'recovery_salt': u.recoverySalt,
                'recovery_created_at': _iso(u.recoveryCreatedAt),
                'recovery_used_at': _iso(u.recoveryUsedAt),
                'recovery_attempts': u.recoveryAttempts,
                'recovery_locked_until': _iso(u.recoveryLockedUntil),
                'login_attempts': u.loginAttempts,
                'login_locked_until': _iso(u.loginLockedUntil),
                'created_at': _iso(u.createdAt),
                'updated_at': _iso(u.updatedAt),
                'deleted_at': _iso(u.deletedAt),
                // Hanya kalau sudah ada: mengirim null akan MENIMPA nomor
                // yang sudah dibagikan server (upsert memperbarui semua
                // kolom yang dikirim).
                if (u.nomorKasir != null) 'nomor_kasir': u.nomorKasir,
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.users).insertOnConflictUpdate(UsersCompanion(
                id: Value(r['id'] as String),
                username: Value(r['username'] as String),
                pinHash: Value(r['pin_hash'] as String),
                salt: Value(r['salt'] as String),
                role: Value(r['role'] as String),
                isActive: Value(r['is_active'] as bool),
                recoveryHash: Value(r['recovery_hash'] as String?),
                recoverySalt: Value(r['recovery_salt'] as String?),
                recoveryCreatedAt: Value(_dt(r['recovery_created_at'])),
                recoveryUsedAt: Value(_dt(r['recovery_used_at'])),
                recoveryAttempts: Value((r['recovery_attempts'] as num).toInt()),
                recoveryLockedUntil: Value(_dt(r['recovery_locked_until'])),
                loginAttempts: Value((r['login_attempts'] as num).toInt()),
                loginLockedUntil: Value(_dt(r['login_locked_until'])),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                // Server sebelum salinan_nama_akun.sql tidak punya kolom ini.
                deletedAt: r.containsKey('deleted_at')
                    ? Value(_dt(r['deleted_at']))
                    : const Value.absent(),
                // Server sebelum nomor_nota.sql tidak punya kolom ini.
                nomorKasir: r.containsKey('nomor_kasir')
                    ? Value((r['nomor_kasir'] as num?)?.toInt())
                    : const Value.absent(),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('users', ids),
      );

  /// Izin per kasir.
  ///
  /// Sebelum v20 tabel ini TIDAK ikut sinkronisasi sama sekali — ia lahir
  /// sebelum aturan sync ada, jadi tidak punya `updated_at` maupun
  /// `sync_status`. Akibatnya izin kasir hanya hidup di HP tempat owner
  /// mengaturnya, dan HP kasir yang dipasang ulang kehilangan seluruhnya:
  /// menu Kasir pun tidak muncul.
  ///
  /// Ditempatkan tepat setelah `users` karena merujuknya lewat foreign key.
  /// `permission_code` juga dirujuk ke tabel `permissions` yang TIDAK
  /// disinkronkan — ia data statis yang disemai sama di setiap pemasangan,
  /// dan harus ikut disemai di server (lihat `supabase/izin.sql`).
  _Entitas _userPermissions() => _Entitas(
        nama: 'user_permissions',
        ambilTertunda: () async {
          final r = await (_db.select(_db.userPermissions)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final up in r)
              {
                'id': up.id,
                'user_id': up.userId,
                'permission_code': up.permissionCode,
                'enabled': up.enabled,
                'created_at': _iso(up.createdAt),
                'updated_at': _iso(up.updatedAt),
                'deleted_at': _iso(up.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.userPermissions)
              .insertOnConflictUpdate(UserPermissionsCompanion(
                id: Value(r['id'] as String),
                userId: Value(r['user_id'] as String),
                permissionCode: Value(r['permission_code'] as String),
                enabled: Value(r['enabled'] as bool),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('user_permissions', ids),
      );

  _Entitas _categories() => _Entitas(
        nama: 'categories',
        ambilTertunda: () async {
          final r = await (_db.select(_db.categories)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final c in r)
              {
                'id': c.id,
                'name': c.name,
                'icon_codepoint': c.iconCodepoint,
                'tampil_di_kasir': c.tampilDiKasir,
                'created_at': _iso(c.createdAt),
                'updated_at': _iso(c.updatedAt),
                'deleted_at': _iso(c.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.categories)
              .insertOnConflictUpdate(CategoriesCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                iconCodepoint: Value(r['icon_codepoint'] as int?),
                // Server yang belum menjalankan kategori_tampil.sql tidak
                // punya kolomnya: nilai di HP dibiarkan, bukan direset.
                tampilDiKasir: r.containsKey('tampil_di_kasir')
                    ? Value(r['tampil_di_kasir'] as bool? ?? true)
                    : const Value.absent(),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('categories', ids),
      );

  _Entitas _products() => _Entitas(
        nama: 'products',
        ambilTertunda: () async {
          final r = await (_db.select(_db.products)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final p in r)
              {
                'id': p.id,
                'name': p.name,
                'price': p.price,
                'category_id': p.categoryId,
                'has_spicy_option': p.hasSpicyOption,
                'has_sweet_option': p.hasSweetOption,
                'has_ice_option': p.hasIceOption,
                'image_path': p.imagePath,
                'created_at': _iso(p.createdAt),
                'updated_at': _iso(p.updatedAt),
                'deleted_at': _iso(p.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.products).insertOnConflictUpdate(ProductsCompanion(
                id: Value(r['id'] as String),
                name: Value(r['name'] as String),
                price: Value((r['price'] as num).toInt()),
                categoryId: Value(r['category_id'] as String?),
                hasSpicyOption: Value(r['has_spicy_option'] as bool),
                // `?? false`: server yang belum menjalankan
                // `supabase/produk_pilihan.sql` tidak punya kolomnya.
                hasSweetOption:
                    Value((r['has_sweet_option'] as bool?) ?? false),
                hasIceOption: Value((r['has_ice_option'] as bool?) ?? false),
                imagePath: Value(r['image_path'] as String?),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('products', ids),
      );

  _Entitas _shifts() => _Entitas(
        nama: 'shifts',
        ambilTertunda: () async {
          final r = await (_db.select(_db.shifts)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final s in r)
              {
                'id': s.id,
                'user_id': s.userId,
                'user_name': s.userName,
                'start_at': _iso(s.startAt),
                'end_at': _iso(s.endAt),
                'kas_awal': s.kasAwal,
                'updated_at': _iso(s.updatedAt),
                'deleted_at': _iso(s.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.shifts).insertOnConflictUpdate(ShiftsCompanion(
                id: Value(r['id'] as String),
                userId: Value(r['user_id'] as String),
                userName: _salinanNama(r, 'user_name'),
                startAt: Value(_dt(r['start_at'])!),
                endAt: Value(_dt(r['end_at'])),
                // Server yang belum menjalankan shift_kas_awal.sql tidak
                // punya kolomnya: nilai di HP dibiarkan, bukan dikosongkan.
                kasAwal: r.containsKey('kas_awal')
                    ? Value((r['kas_awal'] as num?)?.toInt())
                    : const Value.absent(),
                // Diisi server (supabase/shift_gabung.sql); sama seperti
                // kas_awal, server tanpa kolomnya tidak mengosongkan nilai HP.
                digabungKe: r.containsKey('digabung_ke')
                    ? Value(r['digabung_ke'] as String?)
                    : const Value.absent(),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('shifts', ids),
      );

  _Entitas _transactions() => _Entitas(
        nama: 'transactions',
        ambilTertunda: () async {
          final r = await (_db.select(_db.transactions)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final t in r)
              {
                'id': t.id,
                'invoice_no': t.invoiceNo,
                'total': t.total,
                'payment_method': t.paymentMethod,
                'cash_received': t.cashReceived,
                'change': t.change,
                'cashier_user_id': t.cashierUserId,
                'cashier_name': t.cashierName,
                'shift_id': t.shiftId,
                'order_type': t.orderType,
                'bill_name': t.billName,
                'created_at': _iso(t.createdAt),
                'updated_at': _iso(t.updatedAt),
                'deleted_at': _iso(t.deletedAt),
                'cancelled_by_user_id': t.cancelledByUserId,
                'cancelled_by_name': t.cancelledByName,
                'cancel_reason': t.cancelReason,
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.transactions)
              .insertOnConflictUpdate(TransactionsCompanion(
                id: Value(r['id'] as String),
                invoiceNo: Value(r['invoice_no'] as String),
                total: Value((r['total'] as num).toInt()),
                paymentMethod: Value(r['payment_method'] as String),
                cashReceived: Value((r['cash_received'] as num?)?.toInt()),
                change: Value((r['change'] as num?)?.toInt()),
                cashierUserId: Value(r['cashier_user_id'] as String?),
                cashierName: _salinanNama(r, 'cashier_name'),
                shiftId: Value(r['shift_id'] as String?),
                orderType: Value(r['order_type'] as String),
                // Server yang belum menjalankan open_bill.sql tidak punya
                // kolomnya: nilai di HP dibiarkan, bukan dikosongkan.
                billName: r.containsKey('bill_name')
                    ? Value(r['bill_name'] as String?)
                    : const Value.absent(),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                // Kunci yang tidak ada (server belum menjalankan
                // `supabase/transaksi_batal.sql`) terbaca null — aman.
                cancelledByUserId: Value(r['cancelled_by_user_id'] as String?),
                cancelledByName: _salinanNama(r, 'cancelled_by_name'),
                cancelReason: Value(r['cancel_reason'] as String?),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('transactions', ids),
      );

  _Entitas _transactionItems() => _Entitas(
        nama: 'transaction_items',
        ambilTertunda: () async {
          final r = await (_db.select(_db.transactionItems)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final i in r)
              {
                'id': i.id,
                'transaction_id': i.transactionId,
                'product_id': i.productId,
                'product_name': i.productName,
                'qty': i.qty,
                'price_at_sale': i.priceAtSale,
                'subtotal': i.subtotal,
                'notes': i.notes,
                'created_at': _iso(i.createdAt),
                'updated_at': _iso(i.updatedAt),
                'deleted_at': _iso(i.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          await _db
              .into(_db.transactionItems)
              .insertOnConflictUpdate(TransactionItemsCompanion(
                id: Value(r['id'] as String),
                transactionId: Value(r['transaction_id'] as String),
                productId: Value(r['product_id'] as String),
                productName: Value(r['product_name'] as String),
                qty: Value((r['qty'] as num).toInt()),
                priceAtSale: Value((r['price_at_sale'] as num).toInt()),
                subtotal: Value((r['subtotal'] as num).toInt()),
                notes: Value(r['notes'] as String?),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('transaction_items', ids),
      );

  _Entitas _expenses() => _Entitas(
        nama: 'expenses',
        ambilTertunda: () async {
          final r = await (_db.select(_db.expenses)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final e in r)
              {
                'id': e.id,
                'shift_id': e.shiftId,
                'user_id': e.userId,
                'user_name': e.userName,
                'description': e.description,
                'amount': e.amount,
                'category': e.category,
                'qty': e.qty,
                'created_at': _iso(e.createdAt),
                'updated_at': _iso(e.updatedAt),
                'deleted_at': _iso(e.deletedAt),
                'cancelled_by_user_id': e.cancelledByUserId,
                'cancelled_by_name': e.cancelledByName,
                'cancel_reason': e.cancelReason,
              }
          ];
        },
        tulis: (r) async {
          await _db.into(_db.expenses).insertOnConflictUpdate(ExpensesCompanion(
                id: Value(r['id'] as String),
                // Kosong = pengeluaran owner (v33).
                shiftId: Value(r['shift_id'] as String?),
                userId: Value(r['user_id'] as String),
                userName: _salinanNama(r, 'user_name'),
                description: Value(r['description'] as String),
                amount: Value((r['amount'] as num).toInt()),
                // Server sebelum pengeluaran_kategori_wajib.sql bisa kosong.
                category: Value(r['category'] as String? ?? 'bahan_baku'),
                // Server sebelum pengeluaran_kategori.sql tidak mengirim qty.
                qty: Value((r['qty'] as num?)?.toInt() ?? 1),
                createdAt: Value(_dt(r['created_at'])!),
                updatedAt: Value(_dt(r['updated_at'])!),
                deletedAt: Value(_dt(r['deleted_at'])),
                cancelledByUserId: Value(r['cancelled_by_user_id'] as String?),
                cancelledByName: _salinanNama(r, 'cancelled_by_name'),
                cancelReason: Value(r['cancel_reason'] as String?),
                syncStatus: const Value('synced'),
              ));
        },
        tandaiTerkirim: (ids) => _tandai('expenses', ids),
      );

  _Entitas _openBills() => _Entitas(
        nama: 'open_bills',
        ambilTertunda: () async {
          final r = await (_db.select(_db.openBills)
                ..where((t) => t.syncStatus.equals('pending')))
              .get();
          return [
            for (final b in r)
              {
                'id': b.id,
                'name': b.name,
                'shift_id': b.shiftId,
                'user_id': b.userId,
                // jsonb di server — dikirim sebagai daftar, bukan teks.
                'items': jsonDecode(b.items),
                'transaction_id': b.transactionId,
                'created_at': _iso(b.createdAt),
                'updated_at': _iso(b.updatedAt),
                'deleted_at': _iso(b.deletedAt),
              }
          ];
        },
        tulis: (r) async {
          final items = r['items'];
          await _db.into(_db.openBills).insertOnConflictUpdate(
                OpenBillsCompanion(
                  id: Value(r['id'] as String),
                  name: Value(r['name'] as String),
                  shiftId: Value(r['shift_id'] as String),
                  userId: Value(r['user_id'] as String),
                  items: Value(items is String ? items : jsonEncode(items)),
                  transactionId: Value(r['transaction_id'] as String?),
                  createdAt: Value(_dt(r['created_at'])!),
                  updatedAt: Value(_dt(r['updated_at'])!),
                  deletedAt: Value(_dt(r['deleted_at'])),
                  syncStatus: const Value('synced'),
                ),
              );
        },
        tandaiTerkirim: (ids) => _tandai('open_bills', ids),
      );

  // ------------------------------------------------------------------
  // Penanda waktu & konversi
  // ------------------------------------------------------------------

  /// Salinan nama dari server (v35). Kosong — server belum menjalankan
  /// `salinan_nama_akun.sql`, atau barisnya dibuat HP yang belum diperbarui —
  /// TIDAK menimpa salinan yang sudah ada di HP ini: nama tidak pernah sah
  /// kembali kosong.
  static Value<String?> _salinanNama(Map<String, dynamic> r, String kunci) {
    final v = r[kunci] as String?;
    return v == null ? const Value.absent() : Value(v);
  }

  /// Penanda posisi tarikan terakhir, berupa string ISO APA ADANYA dari
  /// server.
  ///
  /// Sengaja tidak pernah diubah jadi `DateTime`. Drift menyimpan `DateTime`
  /// dalam DETIK, sedangkan server memakai MIKRODETIK — sekali dikonversi,
  /// `2026-09-04T10:04:11.430427` menyusut jadi `...11.000000`. Penanda yang
  /// menyusut selalu lebih kecil dari nilai aslinya, sehingga baris terbaru
  /// ikut tertarik lagi di SETIAP sinkronisasi, selamanya.
  Future<String?> _kursorTarikTerakhir(String entitas) async {
    final baris = await (_db.select(_db.syncState)
          ..where((s) => s.entity.equals(entitas)))
        .getSingleOrNull();
    return baris?.lastPulledCursor;
  }

  Future<void> _catatKursorTarik(String entitas, String kursor) async {
    await _db.into(_db.syncState).insertOnConflictUpdate(SyncStateCompanion(
          entity: Value(entitas),
          lastPulledCursor: Value(kursor),
        ));
  }

  /// SQLite menyimpan waktu sebagai detik epoch tanpa zona; PostgreSQL pakai
  /// timestamptz. Konversi selalu lewat UTC supaya tidak bergeser saat
  /// perangkat berpindah zona waktu.
  static String? _iso(DateTime? v) => v?.toUtc().toIso8601String();

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
