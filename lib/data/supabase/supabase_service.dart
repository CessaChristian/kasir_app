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

/// Hasil percobaan mendaftarkan perangkat dengan kunci pemasangan.
enum HasilDaftarPerangkat {
  berhasil,

  /// Server menjawab dan menolak kuncinya. Mengulang dengan kunci yang sama
  /// tidak akan berhasil.
  kunciSalah,

  /// Server tidak terjangkau. Pendaftaran WAJIB online — tanpa server, tidak
  /// ada yang bisa memastikan kuncinya benar.
  jaringan,

  /// Kuncinya benar tapi identitas gagal dibuat.
  gagal,
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

  /// Penanda bahwa perangkat ini sudah pernah didaftarkan.
  ///
  /// Isinya identitas perangkat, bukan rahasia — identitas anonim tidak punya
  /// email maupun password. Yang membuat HP ini tetap dikenali server adalah
  /// SESI-nya, yang diperpanjang sendiri selama HP masih dipakai.
  static const _kunciPerangkatId = 'supabase_perangkat_id';

  // Dua kunci di bawah warisan cara lama, saat kredensial perangkat ditanam
  // ke APK. Masih dibaca supaya HP yang sudah terpasang tidak putus saat
  // aplikasinya diperbarui — dan dibuang begitu pemiliknya menekan
  // "Lepaskan Perangkat" lalu mendaftar ulang.
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

    // Tidak ada lagi kredensial bawaan build yang bisa dicoba. Perangkat yang
    // belum punya sesi harus didaftarkan pemiliknya lewat kunci pemasangan.
    _sebabTerputus ??= SebabTerputus.belumDisiapkan;
    return false;
  }

  /// Sudahkah perangkat ini didaftarkan?
  ///
  /// Termasuk perangkat warisan yang kredensialnya masih tertanam dari cara
  /// lama — supaya pembaruan aplikasi tidak memutus HP yang sedang dipakai.
  Future<bool> sudahTerdaftar() async {
    final id = await _brankas.read(key: _kunciPerangkatId);
    if (id != null && id.isNotEmpty) return true;
    final emailLama = await _brankas.read(key: _kunciEmail);
    return emailLama != null && emailLama.isNotEmpty;
  }

  /// Daftarkan HP ini memakai kunci pemasangan yang diketik pemilik.
  ///
  /// ── KENAPA DUA LANGKAH ──
  ///
  /// Kunci pemasangan cuma untuk MEMBUKTIKAN bahwa yang memasang berhak. Ia
  /// tidak dipakai seterusnya, dan sengaja tidak disimpan di HP — supaya HP
  /// yang hilang tidak membawa serta kemampuan mendaftarkan dirinya lagi.
  ///
  /// Identitas yang dipakai sehari-hari justru yang anonim: tiap HP mendapat
  /// satu yang berbeda. Itulah yang membuat "cabut satu HP" nanti mungkin —
  /// kalau semua HP memakai akun yang sama, server tidak punya cara
  /// membedakannya.
  Future<HasilDaftarPerangkat> daftarkanDenganKunci({
    required String email,
    required String password,
  }) async {
    if (!_siap) return HasilDaftarPerangkat.gagal;
    final auth = Supabase.instance.client.auth;

    try {
      await auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      return golongkanGagalMasuk(e) == SebabTerputus.ditolak
          ? HasilDaftarPerangkat.kunciSalah
          : HasilDaftarPerangkat.jaringan;
    }

    try {
      final hasil = await auth.signInAnonymously();
      final id = hasil.user?.id;
      if (id == null || id.isEmpty) {
        await auth.signOut();
        return HasilDaftarPerangkat.gagal;
      }
      await _brankas.write(key: _kunciPerangkatId, value: id);
      _sebabTerputus = null;
      return HasilDaftarPerangkat.berhasil;
    } catch (e) {
      // Jangan tinggalkan HP ini dalam keadaan masuk sebagai kunci
      // pemasangan — kunci itu bukan identitas yang boleh dipakai bekerja.
      await auth.signOut();
      return golongkanGagalMasuk(e) == SebabTerputus.ditolak
          ? HasilDaftarPerangkat.gagal
          : HasilDaftarPerangkat.jaringan;
    }
  }

  /// Jalur WARISAN: mendaftar memakai email + password perangkat.
  ///
  /// Dipertahankan hanya untuk HP yang sudah terpasang dengan cara lama.
  /// Dihapus setelah semua perangkat dipindahkan.
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
    await _brankas.delete(key: _kunciPerangkatId);
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
