import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../../data/db.dart';
import '../../../../utils/formatters/recovery_code_formatter.dart';
import '../../repositories/auth_repository.dart';
import 'save_recovery_code_page.dart';


/// Page for owner to recover PIN using recovery code
class OwnerRecoveryPage extends StatefulWidget {
  const OwnerRecoveryPage({super.key});

  @override
  State<OwnerRecoveryPage> createState() => _OwnerRecoveryPageState();
}

class _OwnerRecoveryPageState extends State<OwnerRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _recoveryCodeController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  
  final _authRepo = AuthRepository(db);
  
  bool _isLoading = false;
  bool _obscureNewPin = true;
  bool _obscureConfirmPin = true;
  
  // Lock status
  bool _isLocked = false;
  int _lockSecondsRemaining = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
  }

  @override
  void dispose() {
    _recoveryCodeController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockStatus() async {
    final lockStatus = await _authRepo.getOwnerRecoveryLockStatus();
    if (lockStatus.isLocked) {
      setState(() {
        _isLocked = true;
        _lockSecondsRemaining = lockStatus.secondsRemaining;
      });
      _startLockTimer();
    }
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _lockSecondsRemaining--;
        if (_lockSecondsRemaining <= 0) {
          _isLocked = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resetPin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLocked) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authRepo.resetOwnerPinWithRecoveryCode(
        recoveryCode: _recoveryCodeController.text.trim(),
        newPin: _newPinController.text,
      );

      if (!mounted) return;

      if (result.isSuccess && result.newRecoveryCode != null) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN reset successful!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to save new recovery code page
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SaveRecoveryCodePage(
              recoveryCode: result.newRecoveryCode!,
              onComplete: () {
                // Pop back to login page (2 pages: SaveRecoveryCodePage + OwnerRecoveryPage)
                Navigator.of(context).pop(); // Close SaveRecoveryCodePage
                Navigator.of(context).pop(); // Close OwnerRecoveryPage, back to LoginPage
              },
            ),
          ),
        );
      } else if (result.isLocked) {
        setState(() {
          _isLocked = true;
          _lockSecondsRemaining = result.lockSeconds ?? 60;
        });
        _startLockTimer();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Too many attempts'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Invalid recovery code'),
            backgroundColor: Colors.red,
          ),
        );
        
        // Check lock status after failed attempt
        await _checkLockStatus();
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
      appBar: AppBar(
        title: const Text('Owner PIN Recovery'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Icon(
                    Icons.lock_reset,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Reset Owner PIN',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Enter your recovery code and set a new PIN',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Lock warning
                  if (_isLocked)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Too many attempts. Please wait $_lockSecondsRemaining seconds.',
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Recovery code input with auto-format
                  TextFormField(
                    controller: _recoveryCodeController,
                    decoration: InputDecoration(
                      labelText: 'Recovery Code',
                      hintText: 'XXXX-XXXX-XXXX-XXXX',
                      prefixIcon: const Icon(Icons.vpn_key),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    enabled: !_isLocked,
                    inputFormatters: [
                      RecoveryCodeFormatter(), // Auto-format dengan dash
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Recovery code is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // New PIN input
                  TextFormField(
                    controller: _newPinController,
                    obscureText: _obscureNewPin,
                    keyboardType: TextInputType.number,
                    enabled: !_isLocked,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'New PIN (4-6 digits)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNewPin ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureNewPin = !_obscureNewPin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'New PIN is required';
                      }
                      if (value.length < 4 || value.length > 6) {
                        return 'PIN must be 4-6 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm new PIN input
                  TextFormField(
                    controller: _confirmPinController,
                    obscureText: _obscureConfirmPin,
                    keyboardType: TextInputType.number,
                    enabled: !_isLocked,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Confirm New PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPin ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureConfirmPin = !_obscureConfirmPin),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onFieldSubmitted: (_) => _resetPin(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm new PIN';
                      }
                      if (value != _newPinController.text) {
                        return 'PINs do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Reset button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: (_isLoading || _isLocked) ? null : _resetPin,
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
                          : Text(
                              _isLocked 
                                ? 'Locked ($_lockSecondsRemaining s)'
                                : 'Reset PIN',
                              style: const TextStyle(
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
