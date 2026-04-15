import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../repositories/auth_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../recovery/pages/owner_recovery_page.dart';
import '../../../app/app_shell.dart';

/// Login page for owner and cashiers
/// 
/// Authenticates with username and PIN
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _useDropdown = false; // Toggle antara manual/dropdown
  List<String> _availableUsernames = []; // List username dari DB
  String? _selectedUsername; // Username yang dipilih dari dropdown

  @override
  void initState() {
    super.initState();
    _loadUsernames();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadUsernames() async {
    try {
      final authRepo = AuthRepository(db);
      final usernames = await authRepo.getAllActiveUsernames();
      setState(() {
        _availableUsernames = usernames;
      });
    } catch (e) {
      // Silently fail - user can still input manually
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authRepo = AuthRepository(db);
      
      // Get username from dropdown or text input
      final username = _useDropdown 
          ? (_selectedUsername ?? '') 
          : _usernameController.text.trim();
      
      final session = await authRepo.login(
        username: username,
        pin: _pinController.text,
      );

      if (session == null) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid username or PIN'),
            backgroundColor: Colors.red,
          ),
        );
        
        setState(() => _isLoading = false);
        return;
      }

      // Save session
      await SessionManager.instance.setSession(session);

      if (!mounted) return;

      // Navigate to main app
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AppShell(key: AppShell.globalKey)),
      );
      
    } on StateError catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.orange,
        ),
      );
      
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Icon/Logo
                  Icon(
                    Icons.store,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  
                  // Title
                  Text(
                    'POS System',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  
                  Text(
                    'Login to continue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Username field - conditional between dropdown and manual
                  _useDropdown
                      ? DropdownButtonFormField<String>(
                          initialValue: _selectedUsername,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person_outline),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.keyboard),
                              tooltip: 'Switch to manual input',
                              onPressed: () {
                                setState(() {
                                  _useDropdown = false;
                                  if (_selectedUsername != null) {
                                    _usernameController.text = _selectedUsername!;
                                  }
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          hint: const Text('Select username'),
                          items: _availableUsernames.map((username) {
                            return DropdownMenuItem<String>(
                              value: username,
                              child: Text(username),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedUsername = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a username';
                            }
                            return null;
                          },
                        )
                      : TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person_outline),
                            suffixIcon: _availableUsernames.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.arrow_drop_down),
                                    tooltip: 'Select from list',
                                    onPressed: () {
                                      setState(() {
                                        _useDropdown = true;
                                        if (_usernameController.text.isNotEmpty) {
                                          _selectedUsername = _usernameController.text;
                                        }
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          textInputAction: TextInputAction.next,
                          autofocus: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                  const SizedBox(height: 16),

                  // PIN field
                  TextFormField(
                    controller: _pinController,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePin = !_obscurePin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'PIN is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Login button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _login,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Forgot PIN link
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OwnerRecoveryPage(),
                        ),
                      );
                    },
                    child: const Text('Forgot Owner PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
