import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

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

  /// True kalau koneksi Supabase aktif dan device sudah login.
  bool get online => _siap && client?.auth.currentSession != null;

  /// True kalau belum ada sesi aktif.
  bool get currentSessionKosong =>
      !_siap || Supabase.instance.client.auth.currentSession == null;

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
      await _loginUlangDariBrankas();

      // Tahap uji: daftarkan otomatis kalau kredensial diberikan saat build
      // dan perangkat belum pernah didaftarkan.
      if (currentSessionKosong && SupabaseConfig.adaKredensialPerangkat) {
        await daftarkanPerangkat(
          email: SupabaseConfig.deviceEmail,
          password: SupabaseConfig.devicePassword,
        );
      }
    } catch (_) {
      _siap = false;
    }
  }

  /// Daftarkan perangkat ini. Dipanggil SEKALI saat menyiapkan HP.
  ///
  /// Kredensialnya disimpan supaya login berikutnya otomatis — kasir tidak
  /// pernah perlu mengetiknya.
  Future<bool> daftarkanPerangkat({
    required String email,
    required String password,
  }) async {
    if (!_siap) return false;
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      await _brankas.write(key: _kunciEmail, value: email);
      await _brankas.write(key: _kunciPassword, value: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lepaskan perangkat — dipakai kalau HP dialihkan atau dijual.
  Future<void> lepaskanPerangkat() async {
    await _brankas.delete(key: _kunciEmail);
    await _brankas.delete(key: _kunciPassword);
    if (_siap) await Supabase.instance.client.auth.signOut();
  }

  /// Email perangkat yang terdaftar, untuk ditampilkan di layar pengaturan.
  Future<String?> get emailPerangkat => _brankas.read(key: _kunciEmail);

  /// Sesi Supabase punya masa berlaku. Kalau token sudah tidak bisa
  /// diperbarui sendiri (mis. perangkat lama offline), login ulang memakai
  /// kredensial tersimpan.
  Future<void> _loginUlangDariBrankas() async {
    if (Supabase.instance.client.auth.currentSession != null) return;
    final email = await _brankas.read(key: _kunciEmail);
    final password = await _brankas.read(key: _kunciPassword);
    if (email == null || password == null) return;
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
    } catch (_) {
      // Offline atau kredensial dicabut owner. Aplikasi tetap jalan lokal.
    }
  }
}
