import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

/// Tempat Supabase menyimpan "tiket masuk" HP ini: di penyimpanan
/// terenkripsi Android, bukan SharedPreferences biasa (revisi QA B7c).
///
/// Tiket itulah kredensial sungguhan perangkat ini ke server. Di
/// SharedPreferences ia tersimpan sebagai teks biasa — masih butuh HP yang
/// dibongkar untuk mengambilnya, tapi bisa. Identitas perangkatnya sendiri
/// sudah lama disimpan di penyimpanan terenkripsi; tiketnya kini menyusul.
///
/// ── PINDAHAN DARI VERSI LAMA ──
///
/// HP yang sudah terdaftar menyimpan tiketnya di SharedPreferences. Kalau
/// tidak ikut dipindah, HP itu kehilangan sesinya dan harus didaftarkan
/// ulang dengan kunci pemasangan. Maka saat pertama dibuka, tiket lama
/// disalin, salinannya DIPERIKSA, baru yang lama dihapus.
///
/// Kalau penyimpanan terenkripsi bermasalah, SharedPreferences tetap
/// dipakai: kurang aman sementara jauh lebih baik daripada HP kasir yang
/// mendadak tidak bisa sinkron.
class PenyimpananSesiAman extends LocalStorage {
  /// Kunci yang sama dengan bawaan Supabase, supaya pindahannya ketemu.
  final String kunci;

  final FlutterSecureStorage _brankas;
  late SharedPreferences _cadangan;
  var _brankasBisa = true;

  PenyimpananSesiAman({
    required this.kunci,
    FlutterSecureStorage brankas = const FlutterSecureStorage(),
  }) : _brankas = brankas;

  /// Kunci bawaan Supabase untuk [url].
  static String kunciUntuk(String url) =>
      'sb-${Uri.parse(url).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    _cadangan = await SharedPreferences.getInstance();
    try {
      final lama = _cadangan.getString(kunci);
      if (lama == null) return;
      if (await _brankas.read(key: kunci) == null) {
        await _brankas.write(key: kunci, value: lama);
      }
      if (await _brankas.read(key: kunci) != null) {
        await _cadangan.remove(kunci);
      }
    } catch (e) {
      debugPrint('[sesi] penyimpanan terenkripsi tidak bisa dipakai: $e');
      _brankasBisa = false;
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    if (_brankasBisa) {
      try {
        return await _brankas.read(key: kunci);
      } catch (e) {
        debugPrint('[sesi] tiket tak terbaca: $e');
        _brankasBisa = false;
      }
    }
    return _cadangan.getString(kunci);
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _brankas.delete(key: kunci);
    } catch (_) {
      // Tidak ada yang bisa dilakukan; cadangannya tetap dihapus.
    }
    await _cadangan.remove(kunci);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_brankasBisa) {
      try {
        await _brankas.write(key: kunci, value: persistSessionString);
        return;
      } catch (e) {
        debugPrint('[sesi] tiket tak tersimpan: $e');
        _brankasBisa = false;
      }
    }
    await _cadangan.setString(kunci, persistSessionString);
  }
}
