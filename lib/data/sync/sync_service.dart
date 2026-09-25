import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/auth/session_manager.dart';
import '../db.dart';
import '../perangkat/perangkat_repository.dart';
import '../supabase/supabase_service.dart';
import 'kemajuan_sync.dart';
import 'sync_engine.dart';
import 'sync_gambar.dart';

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

  /// Baca penanda waktu yang tersimpan. Panggil sekali di `main()`.
  ///
  /// Disimpan di preferensi, bukan di database, supaya tidak perlu migrasi
  /// skema hanya untuk satu penanda yang boleh hilang tanpa akibat.
  Future<void> muatTerakhirBerhasil() async {
    final p = await SharedPreferences.getInstance();
    final teks = p.getString(_kunciTerakhir);
    if (teks != null) terakhirBerhasil.value = DateTime.tryParse(teks);
  }

  Future<void> _catatBerhasil() async {
    final sekarang = DateTime.now();
    terakhirBerhasil.value = sekarang;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kunciTerakhir, sekarang.toIso8601String());
  }

  /// Jalankan satu putaran, atau ikut menunggu yang sedang berjalan.
  Future<HasilSync> jalankan() => _berjalan ??= _mulai();

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

      final hasil =
          await SyncEngine(db, onKemajuan: (k) => kemajuan.value = k).jalankan();
      if (!hasil.berhasil) return hasil;

      // Berkas gambar menyusul SETELAH barisnya selesai, dan kegagalannya
      // tidak membatalkan apa pun. Kalau digabung, satu gambar yang gagal naik
      // bisa menahan transaksi yang jauh lebih mendesak — padahal gambar yang
      // belum sampai cuma berarti produknya tampil tanpa foto sementara.
      final klien = supabase.client;
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

      // Tandai perangkat ini masih dipakai, supaya pemilik bisa melihat mana
      // yang aktif dan mana yang sudah lama diam di halaman Perangkat.
      // Kegagalannya sengaja tidak mengubah hasil sinkron: daftar perangkat
      // adalah catatan administratif, bukan data dagangan.
      await PerangkatRepository.instance.hadir();

      await _catatBerhasil();
      return lengkap;
    } finally {
      _berjalan = null;
      kemajuan.value = null;
    }
  }
}
