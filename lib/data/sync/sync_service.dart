import '../db.dart';
import 'sync_engine.dart';

/// Pintu tunggal untuk menjalankan sinkronisasi dari mana pun di aplikasi.
///
/// Kenapa perlu lapisan ini, bukan langsung `SyncEngine(db).jalankan()`:
///
/// **Satu putaran pada satu waktu.** Kalau pengguna menarik layar dua kali
/// beruntun — atau menarik saat sinkron pembuka masih berjalan — dua putaran
/// akan berebut menulis `sync_state`. Yang selesai belakangan bisa mencatat
/// penanda waktu yang LEBIH LAMA, sehingga baris yang sudah ditarik akan
/// ditarik ulang, atau lebih buruk: penanda melompati baris yang belum
/// sempat masuk.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool _sedangJalan = false;

  /// True selagi satu putaran sinkron berlangsung.
  bool get sedangJalan => _sedangJalan;

  /// Jalankan satu putaran. Kalau sudah ada yang berjalan, permintaan ini
  /// diabaikan dan ditandai lewat [HasilSync.error].
  Future<HasilSync> jalankan() async {
    if (_sedangJalan) {
      return const HasilSync(error: 'sinkronisasi sedang berjalan');
    }
    _sedangJalan = true;
    try {
      return await SyncEngine(db).jalankan();
    } finally {
      _sedangJalan = false;
    }
  }
}
