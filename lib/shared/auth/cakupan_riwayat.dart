import '../../data/app_database.dart';
import 'session_manager.dart';

/// Seberapa jauh ke belakang sebuah akun boleh melihat catatannya.
enum JenisCakupan {
  /// Owner: semua catatan semua akun.
  semua,

  /// Kasir dengan izin `view_history`: semua catatan miliknya sendiri,
  /// termasuk shift-shift yang sudah lewat.
  milikSendiri,

  /// Kasir tanpa izin itu: hanya shift yang sedang berjalan. Begitu shiftnya
  /// diakhiri dan ia membuka shift baru, riwayatnya mulai dari kosong.
  shiftAktif,
}

/// Cakupan riwayat yang boleh dilihat sesi yang sedang berjalan.
///
/// Dipakai BERSAMA oleh halaman Riwayat (transaksi) dan Pengeluaran, supaya
/// dua halaman itu tidak pernah punya dua versi aturan yang berbeda.
///
/// Melihat catatan kasir LAIN sengaja hanya untuk owner — sejalan dengan izin
/// `view_all_shifts` yang khusus mengatur itu di Pantau Shift.
class CakupanRiwayat {
  final JenisCakupan jenis;

  /// Diisi untuk [JenisCakupan.milikSendiri].
  final String? userId;

  /// Diisi untuk [JenisCakupan.shiftAktif]. Null berarti tidak ada shift
  /// berjalan — tidak ada yang boleh dilihat.
  final String? shiftId;

  const CakupanRiwayat._(this.jenis, {this.userId, this.shiftId});

  factory CakupanRiwayat.dariSesi() {
    final sesi = SessionManager.instance;
    final s = sesi.currentSession;
    if (s == null) {
      return const CakupanRiwayat._(JenisCakupan.shiftAktif);
    }
    if (s.isOwner) return const CakupanRiwayat._(JenisCakupan.semua);
    if (sesi.hasPermission('view_history')) {
      return CakupanRiwayat._(JenisCakupan.milikSendiri, userId: s.userId);
    }
    return CakupanRiwayat._(JenisCakupan.shiftAktif, shiftId: s.shiftId);
  }

  /// Boleh melihat DAFTAR transaksi & pengeluaran [shift] di Detail Shift?
  /// Kartu ringkasannya tetap boleh dilihat siapa pun yang bisa membuka
  /// shift itu.
  ///
  /// Shift yang masih berjalan selalu boleh (Pantau Shift). Shift yang sudah
  /// selesai mengikuti aturan halaman Riwayat: owner semua, pemegang
  /// `view_history` hanya miliknya sendiri, selain itu tidak. Dulu Detail
  /// Shift menjadi pintu samping izin itu (keputusan owner D1, 2026-10-29).
  bool bolehLihatIsiShift(Shift shift) => switch (jenis) {
    JenisCakupan.semua => true,
    _ when shift.endAt == null => true,
    JenisCakupan.milikSendiri => shift.userId == userId,
    JenisCakupan.shiftAktif => false,
  };
}
