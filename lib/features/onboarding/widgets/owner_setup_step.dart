import 'package:flutter/material.dart';

/// Step 1 dari onboarding wizard.
/// Form input untuk setup akun owner: username + PIN.
///
/// Recovery code akan auto-generated dan di-show setelah submit (existing
/// flow dari fitur S7). PIN harus 4 digit numeric.
class OwnerSetupStep extends StatefulWidget {
  final void Function({
    required String username,
    required String pin,
  }) onSubmit;

  const OwnerSetupStep({super.key, required this.onSubmit});

  @override
  State<OwnerSetupStep> createState() => _OwnerSetupStepState();
}

class _OwnerSetupStepState extends State<OwnerSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _usernameC = TextEditingController();
  final _pinC = TextEditingController();
  final _pinConfirmC = TextEditingController();
  bool _obscurePin = true;

  @override
  void dispose() {
    _usernameC.dispose();
    _pinC.dispose();
    _pinConfirmC.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      username: _usernameC.text.trim(),
      pin: _pinC.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              'Setup Akun Owner',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Akun ini adalah owner — punya akses penuh ke semua business.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _usernameC,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'Contoh: sari',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Username wajib diisi';
                if (v.trim().length < 3) return 'Minimal 3 karakter';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinC,
              decoration: InputDecoration(
                labelText: 'PIN (4 digit)',
                hintText: '****',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
              ),
              obscureText: _obscurePin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              validator: (v) {
                if (v == null || v.length != 4) return 'PIN harus 4 digit';
                if (!RegExp(r'^[0-9]{4}$').hasMatch(v)) {
                  return 'PIN harus angka';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _pinConfirmC,
              decoration: const InputDecoration(
                labelText: 'Konfirmasi PIN',
                hintText: '****',
                border: OutlineInputBorder(),
              ),
              obscureText: _obscurePin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Konfirmasi PIN wajib diisi';
                if (v != _pinC.text) return 'PIN tidak cocok';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _handleSubmit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Lanjut'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
