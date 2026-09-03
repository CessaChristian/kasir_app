import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/app_shell.dart';
import 'data/supabase/supabase_service.dart';
import 'data/sync/sync_engine.dart';
import 'shared/services/image_storage_service.dart';
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
  final hasil = await SyncEngine(db).jalankan();
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
  late final Future<AuthState> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _checkAuthState();
  }

  Future<AuthState> _checkAuthState() async {
    final onboardingRepo = OnboardingRepository();
    final hasUser = await onboardingRepo.hasAnyUser();

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

/// Simple model for auth state
class AuthState {
  final bool hasUser;
  final bool hasOwner;
  final bool isLoggedIn;

  AuthState({
    required this.hasUser,
    required this.hasOwner,
    required this.isLoggedIn,
  });
}
