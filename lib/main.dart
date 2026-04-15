import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/app_shell.dart';
import 'data/db.dart';
import 'features/auth/repositories/auth_repository.dart';
import 'features/auth/pages/owner_setup_page.dart';
import 'features/auth/pages/login_page.dart';
import 'shared/auth/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting
  await initializeDateFormatting('id_ID', null);

  // Try to restore session from SharedPreferences
  await SessionManager.instance.restoreSession();

  runApp(const MyApp());
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromRGBO(240, 151, 63, 1),
          primary: const Color.fromRGBO(238, 138, 52, 1),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
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
    final authRepo = AuthRepository(db);
    final hasOwner = await authRepo.hasOwner();
    final isLoggedIn = SessionManager.instance.isLoggedIn;

    return AuthState(
      hasOwner: hasOwner,
      isLoggedIn: isLoggedIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthState>(
      future: _authFuture,
      builder: (context, snapshot) {
        // Loading
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final state = snapshot.data!;

        // No owner exists -> show owner setup
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
  final bool hasOwner;
  final bool isLoggedIn;

  AuthState({
    required this.hasOwner,
    required this.isLoggedIn,
  });
}
