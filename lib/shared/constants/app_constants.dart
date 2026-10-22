/// App-wide constants for Teras Inn POS
class AppConstants {
  AppConstants._();

  // Store Information
  static const String storeName = 'Teras Inn';
  static const String storeAddress = 'Jl. Kemiri Candi, Salatiga';
  static const String storePhone = '08782418921';

  /// Versi yang tampil di Profil. WAJIB sama dengan `version` di
  /// pubspec.yaml (dijaga test). Selama masih tahap pengembangan tetap
  /// 1.0.0. Nomor build (+N) di pubspec tidak boleh turun — HP menolak
  /// update yang nomor build-nya lebih kecil dari yang terpasang.
  static const String versiAplikasi = '1.0.0';
}
