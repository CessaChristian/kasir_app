import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../repositories/auth_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../recovery/pages/save_recovery_code_page.dart';
import '../../../app/app_shell.dart';

/// First-time owner setup page
/// 
/// Only shown when no owner account exists
/// Allows creating the owner account with username and PIN
class OwnerSetupPage extends StatefulWidget {
  const OwnerSetupPage({super.key});

  @override
  State<OwnerSetupPage> createState() => _OwnerSetupPageState();
}

class _OwnerSetupPageState extends State<OwnerSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _setupOwner() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authRepo = AuthRepository(db);
      
      // 1. Create owner account
      final owner = await authRepo.bootstrapOwner(
        username: _usernameController.text.trim(),
        pin: _pinController.text,
      );

      // 2. Generate recovery code
      final recoveryCode = await authRepo.generateAndStoreRecoveryCodeForOwner(owner.id);

      // 3. Auto-login as owner
      final session = await authRepo.login(
        username: _usernameController.text.trim(),
        pin: _pinController.text,
      );

      if (session != null) {
        await SessionManager.instance.setSession(session);

        if (!mounted) return;

        // 4. Navigate to save recovery code page
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SaveRecoveryCodePage(
              recoveryCode: recoveryCode,
              onComplete: () {
                // Navigate to AppShell and clear navigation stack
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => AppShell(key: AppShell.globalKey)),
                  (route) => false,
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                    'Setup Owner Account',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  
                  Text(
                    'Create the owner account to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Username field
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Username is required';
                      }
                      if (value.trim().length < 3) {
                        return 'Username must be at least 3 characters';
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
                      labelText: 'PIN (4-6 digits)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePin = !_obscurePin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'PIN is required';
                      }
                      if (value.length < 4 || value.length > 6) {
                        return 'PIN must be 4-6 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm PIN field
                  TextFormField(
                    controller: _confirmPinController,
                    obscureText: _obscureConfirmPin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Confirm PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPin ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureConfirmPin = !_obscureConfirmPin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _setupOwner(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm PIN';
                      }
                      if (value != _pinController.text) {
                        return 'PINs do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Setup button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _setupOwner,
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
                              'Create Owner Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
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
