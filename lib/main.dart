import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/app_shell.dart';
import 'data/supabase/supabase_config.dart';
import 'data/supabase/supabase_service.dart';
import 'data/sync/sync_service.dart';
import 'shared/services/image_storage_service.dart';
import 'shared/widgets/dialog_sync.dart';
import 'app/app_theme.dart';
import 'data/db.dart';
import 'features/auth/repositories/auth_repository.dart';
import 'features/auth/pages/owner_setup_page.dart';
import 'features/auth/pages/login_page.dart';
import 'features/onboarding/repositories/onboarding_repository.dart';
import 'features/onboarding/pages/onboarding_page.dart';
import 'shared/auth/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting
  await initializeDateFormatting('id_ID', null);

  // Folder gambar di-cache sekali supaya build() bisa menyusun path secara
  // sinkron tanpa FutureBuilder di setiap kartu produk.
  await ImageStorageService.init();

  // Koneksi Supabase. Sengaja tidak melempar error kalau gagal: aplikasi
  // harus tetap jalan penuh secara offline. Kasir tidak boleh gagal
  // berjualan hanya karena server tidak bisa dihubungi.
  await SupabaseService.instance.init();

  // Sinkron pertama dijalankan di latar belakang — TIDAK ditunggu.
  // Menunggunya berarti layar putih selama jaringan lambat, dan aplikasi
  // sudah punya seluruh datanya secara lokal.
  unawaited(_sinkronAwal());

  // Try to restore session from SharedPreferences
  await SessionManager.instance.restoreSession();

  runApp(const MyApp());
}

/// Sinkron saat aplikasi dibuka. Hasilnya dicatat ke log, bukan ditampilkan
/// — antarmukanya menyusul bersama UI baru.
Future<void> _sinkronAwal() async {
  if (!SupabaseService.instance.online) return;
  final hasil = await SyncService.instance.jalankan();
  debugPrint('[sync] $hasil');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
          title: 'Kasir App',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('id', 'ID'),
            Locale('en', 'US'),
          ],
          locale: const Locale('id', 'ID'),
          theme: buildAppTheme(kSeedDineIn),
          home: const AuthFlowHandler(),
        );
  }
}

/// Handles routing based on authentication state
class AuthFlowHandler extends StatefulWidget {
  const AuthFlowHandler({super.key});

  @override
  State<AuthFlowHandler> createState() => _AuthFlowHandlerState();
}

class _AuthFlowHandlerState extends State<AuthFlowHandler> {
  // BUKAN `late final`. Tombol "Coba Lagi" mengganti future ini, dan `final`
  // membuat penggantian kedua melempar LateInitializationError — sehingga
  // setiap percobaan ulang gagal diam-diam: sinkronnya jalan dan datanya
  // masuk, tapi layarnya tidak pernah berubah.
  late Future<AuthState> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _checkAuthState();
  }

  Future<AuthState> _checkAuthState() async {
    final onboardingRepo = OnboardingRepository();
    var hasUser = await onboardingRepo.hasAnyUser();

    // PEMASANGAN PERTAMA — database lokal masih kosong.
    //
    // Kosongnya database TIDAK berarti bisnis ini belum punya akun. Bisa jadi
    // akunnya sudah ada di server dan HP ini cuma belum pernah menariknya.
    // Menebak "belum ada" tanpa bertanya ke server membuat pemilik membuat
    // akun owner KEDUA di HP barunya — dan akun ganda itu ikut tersinkron.
    //
    // Karena itu di sinilah satu-satunya tempat sinkron DITUNGGU. Pemakaian
    // sehari-hari tidak pernah menunggu: begitu ada user lokal, blok ini
    // dilewati dan aplikasi jalan penuh walau offline.
    if (!hasUser && SupabaseConfig.tersedia) {
      final hasil = await SyncService.instance.jalankan();
      if (!hasil.berhasil) {
        return AuthState(
          hasUser: false,
          hasOwner: false,
          isLoggedIn: false,
          perluInternet: true,
        );
      }
      // Periksa ULANG — server mungkin baru saja mengirimkan akunnya.
      hasUser = await onboardingRepo.hasAnyUser();
    }

    if (!hasUser) {
      return AuthState(hasUser: false, hasOwner: false, isLoggedIn: false);
    }

    final authRepo = AuthRepository(db);
    final hasOwner = await authRepo.hasOwner();
    final isLoggedIn = SessionManager.instance.isLoggedIn;

    return AuthState(
      hasUser: true,
      hasOwner: hasOwner,
      isLoggedIn: isLoggedIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthState>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'Terjadi kesalahan saat memulai aplikasi',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _authFuture = _checkAuthState();
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final state = snapshot.data!;

        // Pemasangan pertama tapi server tak terjangkau — JANGAN tawarkan
        // pembuatan akun owner sebelum dipastikan memang belum ada.
        if (state.perluInternet) {
          return _LayarPerluInternet(
            onCobaLagi: () async {
              // Dialog kemajuan menampilkan tabel apa yang sedang ditarik dan
              // sudah berapa barisnya. Tanpa itu layar diam total selama
              // lebih dari semenit dan tombolnya terlihat rusak.
              await DialogSync.tampilkanSelama(context, () async {
                final baru = _checkAuthState();
                setState(() => _authFuture = baru);
                await baru;
              });
            },
          );
        }

        // No user at all (fresh install) -> show onboarding
        if (!state.hasUser) {
          return OnboardingPage(
            onComplete: () {
              // pushAndRemoveUntil — bersihkan OnboardingPage + SaveRecoveryCodePage
              // dari stack supaya back button tidak balik ke onboarding.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          );
        }

        // No owner exists -> show owner setup (legacy path, kept for safety)
        if (!state.hasOwner) {
          return const OwnerSetupPage();
        }

        // Owner exists but not logged in -> show login
        if (!state.isLoggedIn) {
          return const LoginPage();
        }

        // Logged in -> show main app
        return AppShell(key: AppShell.globalKey);
      },
    );
  }
}


/// Ditampilkan saat aplikasi baru dipasang tapi server tidak bisa dihubungi.
///
/// SENGAJA tidak menawarkan jalan pintas "lanjut tanpa internet". Membiarkan
/// pemilik membuat akun di sini berarti membuat akun owner kedua yang ikut
/// tersinkron — dan akun ganda itu tidak bisa dibereskan dari dalam aplikasi.
///
/// Penyiapan pertama HARUS online. Setelahnya aplikasi jalan penuh offline.
class _LayarPerluInternet extends StatefulWidget {
  final Future<void> Function() onCobaLagi;

  const _LayarPerluInternet({required this.onCobaLagi});

  @override
  State<_LayarPerluInternet> createState() => _LayarPerluInternetState();
}

class _LayarPerluInternetState extends State<_LayarPerluInternet> {
  bool _sedangMencoba = false;

  @override
  Widget build(BuildContext context) {
    final warna = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_off_rounded, size: 40, color: warna),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Perlu Internet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Penyiapan pertama butuh koneksi internet untuk mengambil '
                  'data akun dari server.\n\nSetelah ini, aplikasi bisa '
                  'dipakai tanpa internet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  // Menarik seluruh data bisa memakan waktu lebih dari semenit
                  // pada jaringan lambat. Tanpa penanda kemajuan, layar ini
                  // tidak berubah sedikit pun selama proses berjalan dan
                  // tombolnya terlihat rusak — pengguna akan menekan berulang.
                  child: FilledButton.icon(
                    onPressed: _sedangMencoba
                        ? null
                        : () async {
                            setState(() => _sedangMencoba = true);
                            try {
                              await widget.onCobaLagi();
                            } finally {
                              if (mounted) {
                                setState(() => _sedangMencoba = false);
                              }
                            }
                          },
                    icon: _sedangMencoba
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _sedangMencoba ? 'Mengambil data…' : 'Coba Lagi',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple model for auth state
class AuthState {
  final bool hasUser;
  final bool hasOwner;
  final bool isLoggedIn;

  /// Pemasangan pertama, tapi server tidak bisa dihubungi.
  ///
  /// Bedanya dengan `hasUser: false` sangat penting: yang itu berarti
  /// "sudah dipastikan ke server dan memang belum ada siapa-siapa", yang ini
  /// berarti "belum tahu". Menyamakan keduanya membuat pemilik membuat akun
  /// owner KEDUA di HP barunya.
  final bool perluInternet;

  AuthState({
    required this.hasUser,
    required this.hasOwner,
    required this.isLoggedIn,
    this.perluInternet = false,
  });
}
