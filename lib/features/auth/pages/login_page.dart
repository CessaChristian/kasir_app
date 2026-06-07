import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/business_context.dart';
import '../../../data/db.dart';
import '../repositories/auth_repository.dart';
import '../../../shared/auth/session_manager.dart';
import '../recovery/pages/owner_recovery_page.dart';
import '../../../app/app_shell.dart';
import '../../../shared/widgets/app_toast.dart';

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
  List<String> _availableUsernames = [];

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
      if (!mounted) return;
      setState(() => _availableUsernames = usernames);
    } catch (_) {
      // Silent fail — user tetap bisa input manual
    }
  }

  Future<void> _pickUsername() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih Akun',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _availableUsernames.length,
                itemBuilder: (_, i) {
                  final username = _availableUsernames[i];
                  return ListTile(
                    leading: Icon(Icons.person_outline_rounded,
                        color: Colors.grey.shade600),
                    title: Text(username,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    onTap: () => Navigator.pop(ctx, username),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _usernameController.text = selected);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final authRepo = AuthRepository(db);
      final username = _usernameController.text.trim();

      final session = await authRepo.login(
        username: username,
        pin: _pinController.text,
      );

      if (session == null) {
        if (!mounted) return;
        AppToast.error(context, 'Username atau PIN salah');
        setState(() => _isLoading = false);
        return;
      }

      await SessionManager.instance.setSession(session);
      await BusinessContext.instance.loadInitial(userId: session.userId);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AppShell(key: AppShell.globalKey)),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      AppToast.warning(context, e.message);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Terjadi kesalahan: $e');
      setState(() => _isLoading = false);
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
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Column(
            children: [
              // ── Header / Logo ──
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

              // ── Form Section ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Masuk ke akun Anda',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Masukkan username dan PIN untuk melanjutkan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Username ──
                      _buildLabel('Username'),
                      const SizedBox(height: 8),
                      _buildUsernameTextField(),

                      const SizedBox(height: 20),

                      // ── PIN ──
                      _buildLabel('PIN'),
                      const SizedBox(height: 8),
                      _buildPinField(),

                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OwnerRecoveryPage(),
                            ),
                          ),
                          child: Text(
                            'Lupa PIN Owner?',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── Tombol Login ──
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
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
                                  'Masuk',
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

  Widget _buildUsernameTextField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _usernameController,
      textInputAction: TextInputAction.next,
      autofocus: true,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Masukkan username',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(
          Icons.person_outline_rounded,
          color: Colors.grey.shade500,
        ),
        suffixIcon: _availableUsernames.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: Colors.grey.shade500,
                ),
                tooltip: 'Pilih dari daftar',
                onPressed: _pickUsername,
              )
            : null,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Username wajib diisi' : null,
    );
  }


  Widget _buildPinField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _pinController,
      obscureText: _obscurePin,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _login(),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(fontSize: 20, letterSpacing: 8),
      decoration: InputDecoration(
        hintText: '• • • • • •',
        hintStyle: TextStyle(
          color: Colors.grey.shade300,
          fontSize: 16,
          letterSpacing: 4,
        ),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: Colors.grey.shade500,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePin
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey.shade500,
          ),
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
        ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: (v) => v == null || v.isEmpty ? 'PIN wajib diisi' : null,
    );
  }
}
