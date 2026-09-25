import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Kenapa perangkat ini tidak tersambung ke server.
///
/// ── KENAPA DIBEDAKAN ──
///
/// Dulu semua kegagalan menyambung berujung pada satu pesan: "periksa
/// koneksi". Untuk HP yang akses servernya sudah dicabut pemilik, pesan itu
/// menyesatkan — kasir mencabut router, pindah ke kuota, menelepon provider,
/// padahal internetnya baik-baik saja dan tidak ada yang bisa dilakukan dari
/// sisi HP untuk memulihkannya.
///
/// Yang membedakan keduanya: apakah kegagalannya akan PULIH SENDIRI.
enum SebabTerputus {
  /// Server tidak terjangkau — internet mati, sinyal hilang, atau server
  /// sedang gangguan. Pulih sendiri; cukup ditunggu atau dicoba lagi.
  jaringan,

  /// Server terjangkau dan MENJAWAB, tapi menolak kredensial perangkat ini:
  /// passwordnya sudah diganti, atau akunnya dihapus/diblokir. TIDAK akan
  /// pulih sendiri — mencoba ulang atau berganti jaringan tidak ada gunanya.
  ditolak,

  /// Aplikasi tidak punya kredensial perangkat sama sekali, atau Supabase
  /// gagal dimulai. Juga tidak pulih sendiri.
  belumDisiapkan,
}

/// Kode penolakan dari server yang berarti kredensial perangkat ini TIDAK
/// berlaku. Hanya kode-kode ini yang boleh disebut "ditolak".
const _kodeDitolak = {
  'invalid_credentials', // password perangkat sudah diganti
  'user_not_found', //      akun perangkat dihapus
  'user_banned', //         akun perangkat diblokir
  'email_not_confirmed', // akun perangkat belum selesai disiapkan
};

/// Menggolongkan galat dari percobaan login perangkat.
///
/// SENGAJA hanya menyebut "ditolak" kalau server mengatakannya dengan kode
/// yang jelas. Segala yang lain — termasuk 4xx tanpa kode dan 429 karena
/// terlalu sering mencoba — dianggap jaringan. Menuduh "dicabut" tanpa
/// kepastian lebih mahal daripada pesan lama: kasir menelepon pemilik untuk
/// hal yang pulih sendiri, dan pesan yang pernah keliru tidak akan dipercaya
/// lagi saat benar.
///
/// Pembedaannya dapat diandalkan karena gotrue sendiri memisahkannya:
/// permintaan HTTP yang gagal total dan jawaban 5xx dilempar sebagai
/// `AuthRetryableFetchException`, jawaban 4xx sebagai `AuthApiException`
/// lengkap dengan kodenya.
@visibleForTesting
SebabTerputus golongkanGagalMasuk(Object galat) {
  if (galat is AuthApiException && _kodeDitolak.contains(galat.code)) {
    return SebabTerputus.ditolak;
  }
  return SebabTerputus.jaringan;
}

/// Satu-satunya pintu koneksi ke Supabase.
///
/// ARSITEKTUR IDENTITAS — dua hal yang sengaja dipisah:
///
///   Akun Supabase  → menjawab "PERANGKAT ini boleh baca-tulis apa?"
///                    Satu akun per HP, password acak panjang, diketik
///                    sekali saat menyiapkan perangkat.
///
///   PIN + users    → menjawab "SIAPA yang sedang bertugas?"
///                    Murni lokal, tidak pernah menyentuh internet.
///
/// Pemisahan ini penting karena PIN 6 digit hanya punya sejuta kemungkinan.
/// Kalau PIN dipakai sebagai password Supabase, siapa pun bisa mencoba
/// menebaknya lewat API — kunci `anon` tertanam di APK dan bisa dibaca siapa
/// saja. Dengan pemisahan ini, yang menghadap internet adalah kredensial kuat
/// yang tidak pernah diketahui kasir.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const _kunciEmail = 'supabase_device_email';
  static const _kunciPassword = 'supabase_device_password';

  /// Kredensial perangkat disimpan di Keystore (Android) / Keychain (iOS),
  /// bukan SharedPreferences. SharedPreferences itu teks polos di
  /// `/data/data/<paket>/shared_prefs/` dan bisa dibaca begitu saja lewat
  /// `run-as` pada build debug.
  final _brankas = const FlutterSecureStorage();

  bool _siap = false;

  SebabTerputus? _sebabTerputus;

  /// Kenapa percobaan menyambung TERAKHIR gagal, atau null kalau tersambung.
  SebabTerputus? get sebabTerputus => _sebabTerputus;

  /// True kalau koneksi Supabase aktif dan device sudah login.
  bool get online => _siap && sesiMasihBisaDipakai(client?.auth.currentSession);

  /// Apakah tiket ini masih bisa dipakai menyentuh server?
  ///
  /// Sengaja BUKAN sekadar "tiketnya ada". Tiket punya masa berlaku, dan HP
  /// yang didiamkan semalam membukanya lagi dengan tiket yang sudah mati —
  /// lalu sinkronnya ditolak server dan pengguna diberi tahu "periksa
  /// koneksi", padahal internetnya sehat dan yang perlu dilakukan cuma
  /// menukar tiket.
  ///
  /// Masa berlakunya dibaca gotrue dari DALAM tiketnya sendiri, dengan margin
  /// sepuluh detik supaya permintaan yang sedang berjalan tidak kedaluwarsa
  /// di tengah jalan.
  @visibleForTesting
  static bool sesiMasihBisaDipakai(Session? sesi) =>
      sesi != null && !sesi.isExpired;


  /// Null kalau aplikasi dibangun tanpa --dart-define, atau init gagal.
  SupabaseClient? get client => _siap ? Supabase.instance.client : null;

  /// Panggil sekali di main(), SEBELUM runApp.
  ///
  /// Sengaja tidak melempar error: aplikasi harus tetap jalan penuh walau
  /// Supabase tidak tersedia. Kasir tidak boleh gagal berjualan hanya karena
  /// server tidak bisa dihubungi.
  Future<void> init() async {
    if (!SupabaseConfig.tersedia) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
        ),
      );
      _siap = true;
      await pastikanTerhubung();
    } catch (_) {
      _siap = false;
    }
  }

  /// Pastikan ada sesi Supabase yang aktif, mencoba menyambung kalau belum.
  ///
  /// WAJIB dipanggil sebelum setiap putaran sinkron, bukan hanya sekali di
  /// `init()`. Perangkat yang dipasang saat jaringan mati tidak akan pernah
  /// punya sesi; tanpa percobaan ulang, ia tetap dianggap offline selamanya
  /// meski jaringannya sudah pulih — tombol "Coba Lagi" jadi tidak berguna.
  ///
  /// Sesi juga bisa kedaluwarsa kalau perangkat lama tidak dipakai.
  Future<bool> pastikanTerhubung() async {
    if (!_siap) {
      _sebabTerputus = SebabTerputus.belumDisiapkan;
      return false;
    }
    // Sebab dari percobaan sebelumnya tidak boleh terbawa: HP yang tadi
    // offline lalu dicabut harus dilaporkan dicabut, bukan offline.
    _sebabTerputus = null;
    final sesi = Supabase.instance.client.auth.currentSession;
    if (sesiMasihBisaDipakai(sesi)) return true;

    // Tiketnya ada tapi sudah mati — tukar dulu. Ini jalur yang paling sering
    // dilewati setiap pagi: HP menganggur semalam, tiketnya kedaluwarsa, dan
    // penukarannya hampir selalu berhasil dalam sekejap.
    if (sesi != null && await _tukarTiketBasi()) return true;

    // 1. Coba kredensial yang sudah tersimpan di Keystore.
    await _loginUlangDariBrankas();
    if (sesiMasihBisaDipakai(Supabase.instance.client.auth.currentSession)) {
      return true;
    }

    // 2. Belum pernah terdaftar — pakai kredensial dari build.
    if (SupabaseConfig.adaKredensialPerangkat) {
      return daftarkanPerangkat(
        email: SupabaseConfig.deviceEmail,
        password: SupabaseConfig.devicePassword,
      );
    }

    // Tidak ada yang bisa dicoba. Kalau brankas tadi sempat mencoba dan
    // ditolak, sebab itu yang dipertahankan.
    _sebabTerputus ??= SebabTerputus.belumDisiapkan;
    return false;
  }

  /// Daftarkan perangkat ini. Dipanggil SEKALI saat menyiapkan HP.
  ///
  /// Kredensialnya disimpan supaya login berikutnya otomatis — kasir tidak
  /// pernah perlu mengetiknya.
  Future<bool> daftarkanPerangkat({
    required String email,
    required String password,
  }) async {
    if (!_siap) {
      _sebabTerputus = SebabTerputus.belumDisiapkan;
      return false;
    }
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      await _brankas.write(key: _kunciEmail, value: email);
      await _brankas.write(key: _kunciPassword, value: password);
      _sebabTerputus = null;
      return true;
    } catch (e) {
      _sebabTerputus = golongkanGagalMasuk(e);
      return false;
    }
  }

  /// Lepaskan perangkat — dipakai kalau HP dialihkan atau dijual.
  Future<void> lepaskanPerangkat() async {
    await _brankas.delete(key: _kunciEmail);
    await _brankas.delete(key: _kunciPassword);
    if (_siap) await Supabase.instance.client.auth.signOut();
  }

  /// Tukar tiket yang sudah mati dengan yang baru.
  ///
  /// Kegagalannya digolongkan seperti kegagalan login biasa, jadi perangkat
  /// yang aksesnya dicabut ketahuan DI SINI — beberapa detik setelah tiket
  /// lamanya habis — bukan setelah sinkronnya terlanjur ditolak server dengan
  /// pesan yang salah alamat.
  Future<bool> _tukarTiketBasi() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
      return sesiMasihBisaDipakai(
          Supabase.instance.client.auth.currentSession);
    } catch (e) {
      _sebabTerputus = golongkanGagalMasuk(e);
      return false;
    }
  }

  /// Email perangkat yang terdaftar, untuk ditampilkan di layar pengaturan.
  Future<String?> get emailPerangkat => _brankas.read(key: _kunciEmail);

  /// Sesi Supabase punya masa berlaku. Kalau token sudah tidak bisa
  /// diperbarui sendiri (mis. perangkat lama offline), login ulang memakai
  /// kredensial tersimpan.
  Future<void> _loginUlangDariBrankas() async {
    if (sesiMasihBisaDipakai(Supabase.instance.client.auth.currentSession)) {
      return;
    }
    final email = await _brankas.read(key: _kunciEmail);
    final password = await _brankas.read(key: _kunciPassword);
    if (email == null || password == null) return;
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
    } catch (e) {
      // Offline atau kredensial dicabut owner. Aplikasi tetap jalan lokal —
      // tapi JENIS kegagalannya dicatat, supaya layar bisa berkata jujur.
      _sebabTerputus = golongkanGagalMasuk(e);
    }
  }
}
