import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/auth/session_manager.dart';
import '../db.dart';
import '../perangkat/perangkat_repository.dart';
import '../supabase/supabase_service.dart';
import 'kemajuan_sync.dart';
import 'sync_engine.dart';
import 'sync_gambar.dart';
import 'sync_otomatis.dart';

/// Pintu tunggal untuk menjalankan sinkronisasi dari mana pun di aplikasi.
///
/// **Satu putaran pada satu waktu, dan pemanggil lain ikut menunggunya.**
///
/// Kalau dua permintaan datang bersamaan — sinkron pembuka di `main()` dan
/// pemeriksaan pemasangan pertama, atau pengguna menarik layar dua kali —
/// keduanya harus memakai putaran yang SAMA, bukan berebut.
///
/// Sebelumnya permintaan kedua ditolak dengan pesan error. Itu keliru:
/// pemanggil tidak bisa membedakan "gagal karena offline" dari "sedang
/// dikerjakan orang lain", lalu menyimpulkan perangkatnya offline padahal
/// jaringannya baik-baik saja. Membagikan Future yang sama membuat pemanggil
/// kedua menerima hasil sungguhan.
///
/// Dua putaran yang benar-benar berjalan bersamaan juga berbahaya: keduanya
/// menulis `sync_state`, dan yang selesai belakangan bisa mencatat penanda
/// waktu LEBIH LAMA — sehingga baris ditarik ulang, atau penandanya melompati
/// baris yang belum sempat masuk.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  Future<HasilSync>? _berjalan;

  /// Kemajuan putaran yang sedang berjalan, atau null kalau tidak ada.
  ///
  /// Disiarkan lewat ValueNotifier supaya layar mana pun bisa ikut
  /// mendengarkan tanpa perlu tahu siapa yang memulai sinkronnya.
  final ValueNotifier<KemajuanSync?> kemajuan = ValueNotifier(null);

  /// True selagi satu putaran sinkron berlangsung.
  bool get sedangJalan => _berjalan != null;

  static const _kunciTerakhir = 'sync_terakhir_berhasil';

  /// Kapan sinkronisasi terakhir BERHASIL, atau null kalau belum pernah.
  ///
  /// Dipakai untuk memberi tahu kasir seberapa segar datanya. Tanpa ini,
  /// kegagalan sinkron sepenuhnya senyap: layar tetap menampilkan harga lama
  /// dengan yakin, dan tidak ada yang menyadarinya sampai ada pelanggan
  /// terlanjur dibayar dengan harga yang salah.
  final ValueNotifier<DateTime?> terakhirBerhasil = ValueNotifier(null);

  /// Baca penanda waktu yang tersimpan, dan hitung baris tertahan. Panggil
  /// sekali di `main()`.
  ///
  /// Disimpan di preferensi, bukan di database, supaya tidak perlu migrasi
  /// skema hanya untuk satu penanda yang boleh hilang tanpa akibat.
  Future<void> muatTerakhirBerhasil() async {
    final p = await SharedPreferences.getInstance();
    final teks = p.getString(_kunciTerakhir);
    if (teks != null) terakhirBerhasil.value = DateTime.tryParse(teks);
    jumlahGagalKirim.value = p.getInt(_kunciGagalKirim) ?? 0;
    await _hitungTertahan();
  }

  /// Baris HP ini yang DITOLAK server dan tetap tertunda (QA kedua S10).
  /// Ditampilkan di HP ini dan dilaporkan ke server supaya owner melihatnya
  /// di Daftar Perangkat. Hanya diperbarui oleh putaran yang pengirimannya
  /// selesai — koneksi putus tidak berarti barisnya beres.
  final ValueNotifier<int> jumlahGagalKirim = ValueNotifier(0);
  static const _kunciGagalKirim = 'sync_gagal_kirim';

  Future<void> _catatGagalKirim(HasilSync hasil) async {
    final n = hasil.ditolak;
    if (n == null) return;
    jumlahGagalKirim.value = n;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kunciGagalKirim, n);
  }

  /// Jumlah baris server yang tertahan di HP ini (`baris_tertahan`). Hanya
  /// berubah saat menarik, jadi cukup dihitung ulang sesudah tiap putaran.
  final ValueNotifier<int> jumlahTertahan = ValueNotifier(0);

  Future<void> _hitungTertahan() async {
    try {
      jumlahTertahan.value = await db.jumlahTertahan();
    } catch (e) {
      debugPrint('[sync] hitung baris tertahan gagal: $e');
    }
  }

  static const _kunciCocokkan = 'sync_cocokkan_id_terakhir';

  /// Perlu mencocokkan daftar produk & kategori dengan server
  /// ([SyncEngine.cocokkanId])? Ya kalau HP ini baru dipulihkan owner, atau
  /// sudah seminggu — jaring pengaman untuk HP yang dicabut dan dipulihkan
  /// selagi aplikasinya tertutup.
  static Future<bool> perluCocokkanId({DateTime? sekarang}) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(PerangkatRepository.kunciDipulihkan) ?? false) return true;
    final terakhir =
        DateTime.tryParse(p.getString(_kunciCocokkan) ?? '');
    return terakhir == null ||
        (sekarang ?? DateTime.now()).difference(terakhir) >
            const Duration(days: 7);
  }

  Future<void> _catatCocokkanId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(PerangkatRepository.kunciDipulihkan);
    await p.setString(_kunciCocokkan, DateTime.now().toIso8601String());
  }

  Future<void> _catatBerhasil() async {
    final sekarang = DateTime.now();
    terakhirBerhasil.value = sekarang;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kunciTerakhir, sekarang.toIso8601String());
  }

  /// Jalankan satu putaran, atau ikut menunggu yang sedang berjalan.
  Future<HasilSync> jalankan() => _berjalan ??= _mulai();

  /// Mesin putaran yang sedang berjalan — untuk [batalkan].
  SyncEngine? _mesin;

  /// Tombol Batalkan: hentikan putaran yang sedang berjalan di titik aman
  /// berikutnya (lihat [SyncEngine.batalkan]). Tahap foto sesudahnya tidak
  /// ikut jalan, karena hasilnya tidak lagi "berhasil".
  void batalkan() => _mesin?.batalkan();

  /// Tunggu putaran yang sedang berjalan selesai, kalau ada. Hasilnya tidak
  /// dipedulikan, dan paling lama [_batasTunggu] — keluar dari akun tidak
  /// boleh menggantung karena jaringannya tersendat.
  Future<void> tungguSelesai() async {
    final b = _berjalan;
    if (b == null) return;
    try {
      await b.timeout(_batasTunggu);
    } catch (_) {
      // Gagal atau kelamaan: yang ditunggu cuma selesainya.
    }
  }

  static const _batasTunggu = Duration(seconds: 15);

  /// Urutan kerja sesudah mesin sinkron selesai.
  ///
  /// [selamaTersambung] — kabar "HP ini masih aktif" dan pemeriksaan akun,
  /// izin, serta shift — dijalankan WALAU putarannya gagal. Dulu semuanya
  /// ikut berhenti begitu ada satu baris yang ditolak server: setelah 15
  /// menit server menganggap HP ini diam sehingga HP lain boleh menutup
  /// shift yang masih dipakai di sini, dan kasir yang sudah dinonaktifkan
  /// tetap bisa berjualan. Satu baris bermasalah bisa bertahan berhari-hari.
  ///
  /// [hanyaKalauBerhasil] (foto, buang sampah, catatan "terakhir berhasil")
  /// menunggu putaran yang tersambung dan tarikannya selesai
  /// ([HasilSync.bolehRampung]). Dulu menunggu putaran yang BERSIH: satu
  /// baris yang ditolak terus membuat foto tidak pernah terunggah dan
  /// "Sinkron terakhir" membeku (QA kedua S10). Baris yang ditolak sekarang
  /// punya peringatannya sendiri ([jumlahGagalKirim]).
  ///
  /// Saat putarannya gagal, galat pemeriksaan tidak menimpa galat aslinya.
  @visibleForTesting
  static Future<HasilSync> urutanSesudahMesin(
    HasilSync hasil, {
    required Future<HasilSync> Function() hanyaKalauBerhasil,
    required Future<void> Function() selamaTersambung,
  }) async {
    if (!hasil.bolehRampung) {
      try {
        await selamaTersambung();
      } catch (e) {
        debugPrint('[sync] pemeriksaan sesudah sinkron gagal: $e');
      }
      return hasil;
    }
    final lengkap = await hanyaKalauBerhasil();
    await selamaTersambung();
    return lengkap;
  }

  Future<HasilSync> _rampungkan(HasilSync hasil) async {
    // Berkas gambar menyusul SETELAH barisnya selesai, dan kegagalannya
    // tidak membatalkan apa pun. Kalau digabung, satu gambar yang gagal naik
    // bisa menahan transaksi yang jauh lebih mendesak — padahal gambar yang
    // belum sampai cuma berarti produknya tampil tanpa foto sementara.
    final klien = SupabaseService.instance.client;
    var lengkap = hasil;
    if (klien != null) {
      final g = await SyncGambar(db, klien,
              onKemajuan: (k) => kemajuan.value = k)
          .jalankan();
      lengkap = hasil.denganGambar(
        naik: g.diunggah,
        turun: g.diunduh,
        hapus: g.dihapus,
        hapusLokal: g.dihapusLokal,
        error: g.error,
      );
    }

    // Sampah di HP ini dibuang SESUDAH sinkron, supaya status `synced`
    // yang jadi syaratnya sudah mencerminkan kiriman terbaru. Gagalnya
    // tidak mengubah hasil sinkron: sisa sampah cuma memakan sedikit
    // tempat, dan putaran berikutnya mencoba lagi.
    // Sebelum buang sampah lokal: yang disembunyikan di sini ikut terbuang.
    if (await perluCocokkanId()) {
      try {
        final n = await SyncEngine(db).cocokkanId();
        if (n > 0) debugPrint('[sync] $n produk/kategori sudah tidak ada');
        await _catatCocokkanId();
      } catch (e) {
        debugPrint('[sync] cocokkan id gagal: $e');
      }
    }

    try {
      await db.buangSampahLokal();
    } catch (e) {
      debugPrint('[sync] buang sampah lokal gagal: $e');
    }

    await _catatBerhasil();
    return lengkap;
  }

  Future<void> _periksaSesudahSinkron(HasilSync hasil) async {
    // Izin kasir ikut disinkronkan sejak v20, tapi sesi yang sedang berjalan
    // menyimpan daftarnya sejak login. Tanpa dibaca ulang di sini, izin yang
    // baru diberikan pemilik tidak terlihat sampai kasir keluar-masuk lagi —
    // dan tidak ada yang memberi tahu bahwa itu syaratnya.
    await SessionManager.instance.muatUlangIzin();

    // Penonaktifan kasir hanya berlaku kalau ada yang memeriksanya ulang.
    // `is_active` diperiksa saat login dan di restoreSession — keduanya
    // tidak pernah terjadi lagi selama sesi berjalan, jadi tanpa baris ini
    // kasir yang aksesnya sudah dicabut tetap bisa berjualan sampai
    // aplikasinya benar-benar ditutup.
    await SessionManager.instance.periksaAkunMasihBerlaku();

    // Shift yang sudah diakhiri dari perangkat lain harus ketahuan di
    // sini, bukan dibiarkan sampai kasir menjual ke shift yang tutup.
    await SessionManager.instance.periksaShiftMasihBerjalan();

    // Tandai perangkat ini masih dipakai, supaya pemilik bisa melihat mana
    // yang aktif dan mana yang sudah lama diam di halaman Perangkat — dan
    // supaya server tidak menganggap shift di HP ini ditinggalkan.
    // Kegagalannya sengaja tidak mengubah hasil sinkron: daftar perangkat
    // adalah catatan administratif, bukan data dagangan.
    //
    // "Tarikan bersih" hanya kalau semua tabel tertarik DAN tidak ada baris
    // tertahan: HP yang belum menerima semua kabar hapus tidak boleh ikut
    // dianggap "centang biru" oleh buang sampah.
    await PerangkatRepository.instance.hadir(
      SessionManager.instance.currentSession?.shiftId,
      tarikBersih: tarikBersih(hasil, jumlahTertahan.value),
      tertahan: jumlahTertahan.value,
      gagalKirim: jumlahGagalKirim.value,
    );
  }

  /// Boleh dilaporkan ke server sebagai tarikan bersih?
  @visibleForTesting
  static bool tarikBersih(HasilSync hasil, int tertahan) =>
      hasil.tarikSelesai && tertahan == 0;

  HasilSync? _hasilTerakhir;

  /// Data yang ditulis SELAGI putaran berjalan tidak ikut terkirim: tabelnya
  /// mungkin sudah lewat, dan pendengar tulisan sengaja tuli selama sinkron
  /// (SyncOtomatis.perluKirimSetelahTulisan). Dulu data itu menunggu sinkron
  /// berkala sampai 5 menit (QA kedua K10). Sekarang putarannya diulang
  /// sekali — lewat SyncOtomatis, jadi keranjang berisi tetap menahannya.
  Future<void> _ulangiKalauAdaDataBaru(HasilSync h) async {
    try {
      if (!perluUlang(h, await db.jumlahTertunda())) return;
      await SyncOtomatis.instance
          .picu('data baru selama sinkron', abaikanJeda: true);
    } catch (e) {
      debugPrint('[sync] periksa data baru gagal: $e');
    }
  }

  /// Masih ada yang tertunda selain baris yang memang ditolak server, dan
  /// server bisa dijangkau? Koneksi putus atau Batalkan tidak diulang.
  @visibleForTesting
  static bool perluUlang(HasilSync h, int tertunda) {
    if (!h.bolehRampung || h.dibatalkan || h.koneksiPutus) return false;
    return tertunda > (h.ditolak ?? 0);
  }

  Future<HasilSync> _mulai() async {
    try {
      // Pastikan sesinya hidup DULU. Perangkat yang dipasang saat jaringan
      // mati belum pernah punya sesi, dan tanpa percobaan ulang di sini ia
      // akan dianggap offline selamanya meski jaringannya sudah pulih.
      //
      // Hasilnya dulu diabaikan dan SyncEngine yang menolak dengan pesan
      // gabungan "offline atau belum didaftarkan". Akibatnya layar tidak bisa
      // membedakan internet mati dari perangkat yang sudah dicabut, dan
      // menyuruh kasir memeriksa koneksi untuk keduanya.
      final supabase = SupabaseService.instance;
      if (!await supabase.pastikanTerhubung()) {
        final sebab = supabase.sebabTerputus ?? SebabTerputus.jaringan;
        // Identitas HP ini ditolak server: ia dilupakan pemilik. Layar
        // pendaftaran (identitas baru + kunci) menggantikan apa pun yang
        // sedang terbuka — lihat PenjagaPerangkat.
        if (sebab == SebabTerputus.ditolak) {
          await PerangkatRepository.instance.tandaiIdentitasHilang();
        }
        return HasilSync(
          error: 'tidak tersambung: ${sebab.name}',
          sebabTerputus: sebab,
        );
      }
      // Diperiksa SEBELUM mesin sinkron jalan, bukan sesudah.
      //
      // Perangkat yang dicabut dan punya data tertunda akan SELALU gagal
      // mengirim — dan kalau pemeriksaannya ditaruh setelah sinkron berhasil,
      // justru perangkat itu yang tidak pernah sampai ke sana. Yang muncul
      // cuma "periksa koneksi" selamanya, padahal jaringannya sehat dan
      // penyebabnya sudah diketahui server sejak tadi.
      await PerangkatRepository.instance.periksaStatusSaya();

      final mesin = _mesin =
          SyncEngine(db, onKemajuan: (k) => kemajuan.value = k);
      final HasilSync hasil;
      try {
        hasil = await mesin.jalankan();
      } finally {
        _mesin = null;
      }
      // Hanya tarikan yang bisa menambah atau melepas baris tertahan.
      await _hitungTertahan();
      await _catatGagalKirim(hasil);
      return _hasilTerakhir = await urutanSesudahMesin(
        hasil,
        hanyaKalauBerhasil: () => _rampungkan(hasil),
        selamaTersambung: () => _periksaSesudahSinkron(hasil),
      );
    } finally {
      _berjalan = null;
      final h = _hasilTerakhir;
      _hasilTerakhir = null;
      if (h != null) unawaited(_ulangiKalauAdaDataBaru(h));
      kemajuan.value = null;
      // Berhasil atau tidak, HP ini terbukti masih hidup — internet mati
      // tidak dihitung diam (lihat SessionManager.catatKabar).
      try {
        await SessionManager.instance.catatKabar();
      } catch (e) {
        debugPrint('[sync] catat kabar gagal: $e');
      }
    }
  }
}
