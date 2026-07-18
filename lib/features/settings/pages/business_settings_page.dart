import 'package:flutter/material.dart';
import '../../../data/db.dart';
import '../../../data/business_context.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/widgets/app_toast.dart';

/// Pengaturan profil business aktif — edit nama, alamat, telepon.
/// Hanya bisa diakses owner (permission manage_business).
class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameC;
  late final TextEditingController _addressC;
  late final TextEditingController _phoneC;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final biz = BusinessContext.instance.activeBusiness;
    _nameC = TextEditingController(text: biz?.name ?? '');
    _addressC = TextEditingController(text: biz?.address ?? '');
    _phoneC = TextEditingController(text: biz?.phone ?? '');
  }

  @override
  void dispose() {
    _nameC.dispose();
    _addressC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      SessionManager.instance.requireCurrentPermission('manage_business');

      await db.updateActiveBusiness(
        name: _nameC.text.trim(),
        address:
            _addressC.text.trim().isEmpty ? null : _addressC.text.trim(),
        phone: _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim(),
      );

      // Refresh context supaya nama baru langsung muncul di seluruh UI
      final userId = SessionManager.instance.currentUserId!;
      await BusinessContext.instance.refreshActiveBusiness(userId: userId);

      if (!mounted) return;
      AppToast.success(context, 'Profil business berhasil disimpan');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal menyimpan: $e');
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz = BusinessContext.instance.activeBusiness;
    final typeLabel = biz?.type == 'restaurant_dinein'
        ? 'Restaurant Dine-in'
        : 'Beverage Grab-and-Go';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pengaturan Business'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info tipe (read-only — tipe tidak bisa diubah setelah dibuat
              // karena menentukan flow kasir)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      biz?.type == 'restaurant_dinein'
                          ? Icons.restaurant_rounded
                          : Icons.local_cafe_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tipe Business',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                        Text(
                          typeLabel,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameC,
                decoration: const InputDecoration(
                  labelText: 'Nama Business',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressC,
                decoration: const InputDecoration(
                  labelText: 'Alamat (opsional)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneC,
                decoration: const InputDecoration(
                  labelText: 'No. Telepon (opsional)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 28),

              FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Simpan',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
