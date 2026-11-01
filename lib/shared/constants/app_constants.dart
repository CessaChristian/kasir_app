/// App-wide constants for Teras Inn POS
class AppConstants {
  AppConstants._();

  // Store Information
  static const String storeName = 'Teras Inn';
  static const String storeAddress = 'Jl. Kemiri Candi, Salatiga';
  static const String storePhone = '087859665084';

  /// Alamat di nota cetak — lebih pendek dari [storeAddress] supaya muat
  /// satu baris kertas 58 mm, seperti nota lama Teras Inn.
  static const String alamatNota = 'Jl. Kemiri Candi';

  /// WiFi pelanggan, dicetak di bawah nota (keputusan owner 2026-11-01).
  static const String wifiNama = 'TERAS INN';
  static const String wifiSandi = 'terasinspirasi';

  /// Versi yang tampil di Profil. WAJIB sama dengan `version` di
  /// pubspec.yaml (dijaga test). Selama masih tahap pengembangan tetap
  /// 1.0.0. Nomor build (+N) di pubspec tidak boleh turun — HP menolak
  /// update yang nomor build-nya lebih kecil dari yang terpasang.
  static const String versiAplikasi = '1.0.0';
}
