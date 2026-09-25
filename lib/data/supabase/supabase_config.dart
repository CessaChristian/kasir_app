/// Alamat dan kunci publik project Supabase.
///
/// ── KENAPA DITEMPEL DI SINI, BUKAN LEWAT --dart-define ──
///
/// Dulu dua nilai ini diberikan saat build dengan alasan keamanan. Alasan itu
/// SALAH, dan sudah dibuktikan: nilai `--dart-define` ikut terkompilasi ke
/// dalam APK persis seperti kalau ditulis di sini. Satu perintah `strings`
/// pada `libapp.so` build RELEASE mengeluarkan URL-nya 18 kali. Jadi dari sisi
/// kerahasiaan APK, keduanya sama saja — tidak ada yang disembunyikan.
///
/// Yang TIDAK sama adalah akibat kalau lupa menuliskannya. `tersedia` di bawah
/// bernilai false saat keduanya kosong, dan aplikasi diam-diam berubah jadi
/// aplikasi offline murni: tidak menyinkron apa pun, tanpa satu pun tanda di
/// layar. Pernah terjadi — APK release tanpa flag langsung menampilkan "Setup
/// Akun Owner" seolah server tidak ada, dan baru ketahuan setelah ditelusuri.
///
/// Dengan ditempel di sini, kelalaian itu menjadi MUSTAHIL, bukan sekadar
/// diperingatkan.
///
/// ── KENAPA KEDUANYA AMAN DI REPOSITORI PUBLIK ──
///
/// `url` muncul di setiap permintaan jaringan; menyembunyikannya tidak masuk
/// akal. `anonKey` memang dirancang publik — ia hanya menyatakan "saya
/// aplikasi Teras Inn". Sudah dibuktikan langsung ke server: dengan kunci ini
/// saja tanpa login, permintaan baca mengembalikan NOL baris. RLS yang
/// menahan, bukan kerahasiaan kuncinya.
///
/// Kredensial PERANGKAT beda cerita — lihat catatannya di bawah.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = 'https://ejvfbmmaiaqxcouiurws.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVqdmZibW1haWFxeGNvdWl1cndzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyMzgwMjQsImV4cCI6MjEwMzgxNDAyNH0.UjQ1nyTjyNNPWlPajyYZUNYU55krz1KZmikOa5T_IfY';

  // Kredensial perangkat SENGAJA tidak ada di sini lagi.
  //
  // Dulu email dan password perangkat ditanam saat build lewat --dart-define,
  // sehingga setiap HP baru butuh APK sendiri dan rahasianya bisa dikorek dari
  // berkas APK — sudah dibuktikan bisa. Sekarang perangkat mendapat
  // identitasnya sendiri saat didaftarkan pemilik, dan identitas itu tidak
  // pernah meninggalkan HP yang bersangkutan.
  //
  // Akibatnya APK tidak lagi memuat satu pun rahasia: `url` dan `anonKey` di
  // atas memang dirancang publik.

  /// Selalu true sekarang, dan itu memang tujuannya — lihat catatan di atas.
  ///
  /// Tetap dipertahankan sebagai satu tempat bertanya "apakah servernya
  /// dikonfigurasi", supaya pemanggil tidak perlu tahu caranya diisi. Test
  /// penjaga memastikan nilainya tidak diam-diam kembali bisa false.
  static bool get tersedia => url.isNotEmpty && anonKey.isNotEmpty;
}
