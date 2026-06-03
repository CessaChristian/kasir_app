import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../repositories/auth_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../recovery/pages/save_recovery_code_page.dart';
import '../../../app/app_shell.dart';
import '../../../shared/widgets/app_toast.dart';

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

      final owner = await authRepo.bootstrapOwner(
        username: _usernameController.text.trim(),
        pin: _pinController.text,
      );

      final recoveryCode =
          await authRepo.generateAndStoreRecoveryCodeForOwner(owner.id);

      final session = await authRepo.login(
        username: _usernameController.text.trim(),
        pin: _pinController.text,
      );

      if (session != null) {
        await SessionManager.instance.setSession(session);
        if (!mounted) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SaveRecoveryCodePage(
              recoveryCode: recoveryCode,
              // ctx = context milik SaveRecoveryCodePage, selalu valid
              onComplete: (ctx) {
                Navigator.of(ctx).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => AppShell(key: AppShell.globalKey)),
                  (route) => false,
                );
              },
            ),
          ),
        );
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
      backgroundColor: const Color(0xFFF8F5F0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: viewInsets.bottom + 24),
          child: Column(
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 52, 24, 40),
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
                    // Logo
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/Logo Teras Inn.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, err, stack) => Icon(
                            Icons.restaurant_rounded,
                            size: 56,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Teras Inn',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'POS Sistem',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Keterangan Setup ──
              Container(
                margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Selamat datang! Buat akun Owner untuk memulai menggunakan aplikasi.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Form ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buat Akun Owner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Akun ini hanya dibuat sekali dan tidak bisa diubah',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 24),

                      // ── Username ──
                      _buildLabel('Username'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        autofocus: true,
                        style: const TextStyle(fontSize: 15),
                        decoration: _inputDecoration(
                          hint: 'Masukkan nama pengguna',
                          icon: Icons.person_outline_rounded,
                          colorScheme: colorScheme,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Username wajib diisi';
                          }
                          if (v.trim().length < 3) {
                            return 'Username minimal 3 karakter';
                          }
                          if (v.trim().length > 30) {
                            return 'Username maksimal 30 karakter';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── PIN ──
                      _buildLabel('PIN (4–6 digit)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pinController,
                        obscureText: _obscurePin,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(
                            fontSize: 20, letterSpacing: 8),
                        decoration: _inputDecoration(
                          hint: '• • • • • •',
                          icon: Icons.lock_outline_rounded,
                          colorScheme: colorScheme,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePin
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade500,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePin = !_obscurePin),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'PIN wajib diisi';
                          }
                          if (v.length < 4 || v.length > 6) {
                            return 'PIN harus 4–6 digit';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── Konfirmasi PIN ──
                      _buildLabel('Konfirmasi PIN'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _confirmPinController,
                        obscureText: _obscureConfirmPin,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _setupOwner(),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(
                            fontSize: 20, letterSpacing: 8),
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
                                () => _obscureConfirmPin = !_obscureConfirmPin),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Konfirmasi PIN wajib diisi';
                          }
                          if (v != _pinController.text) {
                            return 'PIN tidak cocok';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // ── Tombol Buat Akun ──
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _setupOwner,
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
                              : const Text(
                                  'Buat Akun Owner',
                                  style: TextStyle(
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
        fontSize: hint.contains('•') ? 16 : 14,
        letterSpacing: hint.contains('•') ? 4 : 0,
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
