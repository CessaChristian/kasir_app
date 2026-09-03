/// Alamat dan kunci publik project Supabase.
///
/// Nilainya diberikan saat build lewat `--dart-define`, BUKAN ditulis di sini.
/// Kunci `anon` memang aman tertanam di dalam APK — dia hanya menyatakan
/// "saya aplikasi Teras Inn", dan tidak memberi akses apa pun tanpa login
/// (sudah dibuktikan: role anon membaca nol baris). Tapi menuliskannya di
/// dalam kode berarti ia ikut ke repositori publik, dan itu memudahkan orang
/// menemukan project ini tanpa alasan.
///
/// Cara build:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Kredensial perangkat, HANYA untuk tahap uji coba.
  ///
  /// Nanti diganti layar "Daftarkan Perangkat" yang diketik sekali oleh
  /// pemilik saat menyiapkan HP. Ditaruh di --dart-define supaya tidak
  /// pernah tertulis di dalam kode maupun repositori.
  static const String deviceEmail =
      String.fromEnvironment('SUPABASE_DEVICE_EMAIL');
  static const String devicePassword =
      String.fromEnvironment('SUPABASE_DEVICE_PASSWORD');

  static bool get adaKredensialPerangkat =>
      deviceEmail.isNotEmpty && devicePassword.isNotEmpty;

  /// False kalau aplikasi dibangun tanpa --dart-define. Dipakai supaya
  /// aplikasi tetap jalan sepenuhnya offline, bukan gagal saat start.
  static bool get tersedia => url.isNotEmpty && anonKey.isNotEmpty;
}
