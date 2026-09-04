import '../db.dart';
import '../supabase/supabase_service.dart';
import 'sync_engine.dart';

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

  /// True selagi satu putaran sinkron berlangsung.
  bool get sedangJalan => _berjalan != null;

  /// Jalankan satu putaran, atau ikut menunggu yang sedang berjalan.
  Future<HasilSync> jalankan() => _berjalan ??= _mulai();

  Future<HasilSync> _mulai() async {
    try {
      // Pastikan sesinya hidup DULU. Perangkat yang dipasang saat jaringan
      // mati belum pernah punya sesi, dan tanpa percobaan ulang di sini ia
      // akan dianggap offline selamanya meski jaringannya sudah pulih.
      await SupabaseService.instance.pastikanTerhubung();
      return await SyncEngine(db).jalankan();
    } finally {
      _berjalan = null;
    }
  }
}
