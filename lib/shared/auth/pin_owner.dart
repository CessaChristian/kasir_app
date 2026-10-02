import 'package:drift/drift.dart' show OrderingTerm;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_database.dart';
import '../../utils/crypto_utils.dart';

/// Memeriksa PIN owner untuk persetujuan pembatalan oleh kasir — transaksi
/// maupun pengeluaran memakai pemeriksa yang SAMA, jadi aturannya dan
/// kuncinya tidak bisa berbeda.
///
/// Dicek di HP ini (bisa offline). Salah [batasGagal] kali mengunci
/// pembatalan selama [lamaTerkunci] — HANYA di HP ini dan hanya untuk
/// pembatalan. Login owner sengaja tidak ikut terkunci: kalau ikut, kasir
/// yang menebak-nebak PIN bisa mengunci owner keluar.
class PemeriksaPinOwner {
  final AppDatabase _db;
  PemeriksaPinOwner(this._db);

  static const _kunciGagal = 'batal_pin_gagal';
  static const _kunciTerkunciSampai = 'batal_pin_terkunci_sampai';
  static const batasGagal = 5;
  static const lamaTerkunci = Duration(minutes: 5);

  /// Melempar [StateError] kalau PIN salah atau sedang terkunci.
  Future<void> periksa(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final sampai =
        DateTime.tryParse(prefs.getString(_kunciTerkunciSampai) ?? '');
    if (sampai != null && sampai.isAfter(DateTime.now())) {
      final menit = sampai.difference(DateTime.now()).inMinutes + 1;
      throw StateError('Terlalu banyak PIN salah. Coba lagi $menit menit lagi.');
    }

    final owner = await (_db.select(_db.users)
          ..where((u) => u.role.equals('owner'))
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    final cocok =
        owner != null && CryptoUtils.verifyPin(pin, owner.salt, owner.pinHash);

    if (cocok) {
      await prefs.remove(_kunciGagal);
      await prefs.remove(_kunciTerkunciSampai);
      return;
    }

    final gagal = (prefs.getInt(_kunciGagal) ?? 0) + 1;
    if (gagal >= batasGagal) {
      await prefs.remove(_kunciGagal);
      await prefs.setString(_kunciTerkunciSampai,
          DateTime.now().add(lamaTerkunci).toIso8601String());
    } else {
      await prefs.setInt(_kunciGagal, gagal);
    }
    throw StateError('PIN salah.');
  }
}
