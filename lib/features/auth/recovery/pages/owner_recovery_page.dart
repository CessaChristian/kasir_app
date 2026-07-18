import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../data/db.dart';
import '../../../../utils/formatters/recovery_code_formatter.dart';
import '../../repositories/auth_repository.dart';
import 'save_recovery_code_page.dart';

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
        AppToast.success(context, 'PIN berhasil direset');

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SaveRecoveryCodePage(
              recoveryCode: result.newRecoveryCode!,
              // ctx = context milik SaveRecoveryCodePage, selalu valid
              onComplete: (ctx) {
                Navigator.of(ctx).pop(); // Tutup SaveRecoveryCodePage
                Navigator.of(ctx).pop(); // Tutup OwnerRecoveryPage
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

        AppToast.warning(context, result.message ?? 'Terlalu banyak percobaan');
      } else {
        AppToast.error(context, result.message ?? 'Kode recovery tidak valid');
        await _checkLockStatus();
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Terjadi kesalahan: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: viewInsets.bottom + 24),
          child: Column(
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 12,
                  24,
                  36,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        color: Colors.grey.shade700,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        size: 40,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reset PIN Owner',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Masukkan kode recovery dan buat PIN baru',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Form Section ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Lock Warning ──
                      if (_isLocked)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer_rounded,
                                color: Colors.red.shade500,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Terlalu banyak percobaan. Tunggu $_lockSecondsRemaining detik.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Kode Recovery ──
                      _buildLabel('Kode Recovery'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _recoveryCodeController,
                        enabled: !_isLocked,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          fontSize: 16,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                        inputFormatters: [
                          RecoveryCodeFormatter(),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-]'),
                          ),
                        ],
                        decoration: _inputDecoration(
                          hint: 'XXXX-XXXX-XXXX-XXXX',
                          icon: Icons.vpn_key_rounded,
                          colorScheme: colorScheme,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Kode recovery wajib diisi'
                            : null,
                      ),

                      const SizedBox(height: 20),

                      // ── PIN Baru ──
                      _buildLabel('PIN Baru'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _newPinController,
                        obscureText: _obscureNewPin,
                        enabled: !_isLocked,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(fontSize: 20, letterSpacing: 8),
                        decoration: _inputDecoration(
                          hint: '• • • • • •',
                          icon: Icons.lock_outline_rounded,
                          colorScheme: colorScheme,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPin
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade500,
                            ),
                            onPressed: () => setState(
                              () => _obscureNewPin = !_obscureNewPin,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'PIN baru wajib diisi';
                          }
                          if (v.length < 4 || v.length > 6) {
                            return 'PIN harus 4-6 digit';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── Konfirmasi PIN ──
                      _buildLabel('Konfirmasi PIN Baru'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _confirmPinController,
                        obscureText: _obscureConfirmPin,
                        enabled: !_isLocked,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _resetPin(),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(fontSize: 20, letterSpacing: 8),
                        decoration: _inputDecoration(
                          hint: '• • • • • •',
                          icon: Icons.lock_outline_rounded,
                          colorScheme: colorScheme,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPin
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade500,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPin = !_obscureConfirmPin,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Konfirmasi PIN wajib diisi';
                          }
                          if (v != _newPinController.text) {
                            return 'PIN tidak cocok';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // ── Tombol Reset ──
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isLocked)
                              ? null
                              : _resetPin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isLocked
                                      ? 'Tunggu $_lockSecondsRemaining detik...'
                                      : 'Reset PIN',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required ColorScheme colorScheme,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey.shade300,
        fontSize: 16,
        letterSpacing: hint.contains('•') ? 4 : 1,
      ),
      prefixIcon: Icon(icon, color: Colors.grey.shade500),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade100),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
