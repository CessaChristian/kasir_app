import 'package:flutter/material.dart';

/// Step 2 dari onboarding wizard.
/// Form input untuk setup business pertama.
class BusinessSetupStep extends StatefulWidget {
  final void Function({
    required String name,
    required String type,
    String? address,
    String? phone,
  }) onSubmit;

  final VoidCallback onBack;

  const BusinessSetupStep({
    super.key,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  State<BusinessSetupStep> createState() => _BusinessSetupStepState();
}

class _BusinessSetupStepState extends State<BusinessSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _addressC = TextEditingController();
  final _phoneC = TextEditingController();
  String _type = 'restaurant_dinein';

  @override
  void dispose() {
    _nameC.dispose();
    _addressC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      name: _nameC.text.trim(),
      type: _type,
      address: _addressC.text.trim().isEmpty ? null : _addressC.text.trim(),
      phone: _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim(),
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
              'Setup Business Pertama',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Bisa ditambah business kedua nanti dari Settings.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameC,
              decoration: const InputDecoration(
                labelText: 'Nama Business',
                hintText: 'Contoh: Teras Inn',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nama wajib diisi';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Tipe Business:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v!),
              child: Column(
                children: const [
                  RadioListTile<String>(
                    title: Text('Restaurant / Cafe (Dine-in)'),
                    subtitle: Text('Customer duduk lama, order di tempat'),
                    value: 'restaurant_dinein',
                  ),
                  RadioListTile<String>(
                    title: Text('Beverage Grab-and-Go'),
                    subtitle: Text('Kios minuman, antrian cepat'),
                    value: 'beverage_grabandgo',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressC,
              decoration: const InputDecoration(
                labelText: 'Alamat (opsional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneC,
              decoration: const InputDecoration(
                labelText: 'No. Telepon (opsional)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Kembali'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _handleSubmit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Buat'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
