/// App-wide constants for Teras Inn POS
class AppConstants {
  AppConstants._();

  // Store Information
  static const String storeName = 'Teras Inn';
  static const String storeAddress = 'Jl. Kemiri Candi, Salatiga';
  static const String storePhone = '08782418921';

  /// Versi yang tampil di Profil. WAJIB sama dengan `version` di
  /// pubspec.yaml (dijaga test). Setiap APK baru untuk HP kasir menaikkan
  /// versi ini DAN nomor build (+N) di pubspec — HP menolak update yang
  /// nomor build-nya tidak lebih besar.
  static const String versiAplikasi = '1.0.2';
}
