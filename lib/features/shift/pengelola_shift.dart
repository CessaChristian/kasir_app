import 'dart:async';

import '../../data/app_database.dart';
import '../../data/perangkat/perangkat_repository.dart';
import '../../data/supabase/supabase_service.dart';
import '../../data/sync/sync_otomatis.dart';
import '../../shared/auth/session_manager.dart';
import '../auth/repositories/auth_repository.dart';
import 'repositories/shift_repository.dart';

/// Buka dan tutup shift kasir yang sedang masuk — database, sesi, dan
/// penanda perangkat diurus di satu tempat.
///
/// Sejak v37 shift tidak lagi dibuka otomatis saat login: kasir membukanya
/// sendiri sambil mencatat kas awal, dan menutupnya dari Profil tanpa harus
/// keluar dari akun (keputusan owner 2026-10-13, sesuai desain).
class PengelolaShift {
  final ShiftRepository _repo;
  final AuthRepository _auth;

  /// Diisi test: jawaban server "siapa lagi yang memegang shift ini?".
  /// Bawaan: tanya server lewat [PerangkatRepository].
  final Future<List<PemegangShift>> Function(String shiftId)? _pemegangLain;

  /// Diisi test. Bawaan: [SupabaseService.online].
  final bool Function()? _online;

  PengelolaShift(
    AppDatabase db, {
    Future<List<PemegangShift>> Function(String shiftId)? pemegangLain,
    bool Function()? online,
  }) : _repo = ShiftRepository(db),
       _auth = AuthRepository(db),
       _pemegangLain = pemegangLain,
       _online = online;

  /// Buka shift dengan [kasAwal]. True kalau yang dipakai ternyata shift
  /// lama yang masih berjalan (dibuka di HP lain) — kas awalnya tidak
  /// diubah.
  Future<bool> buka(int kasAwal) async {
    final sesi = SessionManager.instance.currentSession;
    if (sesi == null) throw StateError('Belum masuk');
    SessionManager.instance.requirePermission('open_close_shift');

    final lama = await _auth.cariShiftTerbuka(sesi.userId);
    final id =
        lama ?? await _repo.bukaShift(userId: sesi.userId, kasAwal: kasAwal);
    await SessionManager.instance.aturShift(id);
    unawaited(_auth.laporShift(id));

    // Awal kerja: pastikan kasir memulai dari daftar produk dan harga yang
    // terbaru, dan shift barunya segera sampai ke HP lain. Sengaja tidak
    // ditunggu — shift tidak boleh gagal dibuka karena jaringannya mati.
    unawaited(SyncOtomatis.instance.picu('shift dibuka', abaikanJeda: true));
    return lama != null;
  }

  /// Alasan shift ini belum boleh ditutup, atau null kalau boleh.
  ///
  /// Sengaja MENOLAK saat tidak bisa bertanya ke server. "Tidak tahu" dan
  /// "tidak ada yang memegang" adalah dua hal yang sangat berbeda di sini:
  /// menebak yang kedua berarti menutup shift yang mungkin masih dipakai
  /// rekannya, dan kerusakannya baru ketahuan di rekap keesokan harinya.
  Future<String?> halanganMenutup(String shiftId) async {
    if (!(_online ?? () => SupabaseService.instance.online)()) {
      return 'Butuh internet untuk menutup shift, supaya perangkat lain yang '
          'mungkin masih memakai shift ini tidak ikut terputus.';
    }
    try {
      final pemegang =
          await (_pemegangLain ??
              PerangkatRepository.instance.pemegangShiftLain)(shiftId);
      if (pemegang.isEmpty) return null;
      return pesanDipegang(pemegang);
    } catch (_) {
      return 'Tidak bisa memastikan ke server apakah perangkat lain masih '
          'memakai shift ini. Coba lagi sebentar.';
    }
  }

  /// Pesan penolakan yang menyebut perangkat pemegangnya — tanpa nama, kasir
  /// tidak tahu harus mencari HP yang mana.
  ///
  /// Perangkat yang sudah [SessionManager.batasDiam] tidak memberi kabar
  /// tidak dihitung server lagi, jadi pesannya juga menyebut kapan shift
  /// bisa ditutup kalau perangkat itu ternyata sudah mati.
  static String pesanDipegang(List<PemegangShift> pemegang) {
    String aktif(Duration d) => d.inMinutes < 1
        ? 'aktif baru saja'
        : 'aktif ${d.inMinutes} menit lalu';
    final nama = [for (final p in pemegang) '${p.nama} (${aktif(p.diam)})'];
    final daftar = nama.length == 1
        ? nama.single
        : '${nama.sublist(0, nama.length - 1).join(', ')} dan ${nama.last}';
    final tersegar = pemegang
        .map((p) => p.diam)
        .reduce((a, b) => a < b ? a : b);
    final sisa = SessionManager.batasDiam - tersegar;
    final menit = (sisa.inSeconds / 60).ceil().clamp(1, 1 << 20);
    final itu = pemegang.length == 1 ? 'perangkat itu' : 'perangkat-perangkat itu';
    return 'Shift ini masih dipakai di $daftar. Tutup shift dari $itu. '
        'Kalau $itu sudah tidak dipakai, shift bisa ditutup sekitar '
        '$menit menit lagi.';
  }

  /// Tutup shift berjalan. Kasir tetap masuk dan bisa membuka shift baru.
  /// Panggil [halanganMenutup] lebih dulu.
  Future<void> tutup() async {
    final shiftId = SessionManager.instance.currentSession?.shiftId;
    if (shiftId == null) return;
    await _repo.tutupShift(shiftId);
    await SessionManager.instance.aturShift(null);
    // Lepaskan tanda "perangkat ini memegang shift X" di server; best-effort.
    unawaited(PerangkatRepository.instance.hadir(null));
    unawaited(SyncOtomatis.instance.picu('shift ditutup', abaikanJeda: true));
  }
}
