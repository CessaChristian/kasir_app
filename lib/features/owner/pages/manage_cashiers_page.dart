import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../../../data/app_database.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/recovery/pages/save_recovery_code_page.dart';
import '../repositories/cashier_repository.dart';
import 'user_permissions_page.dart';

/// Page for owner to manage cashier accounts
/// 
/// Allows creating, viewing, activating/deactivating cashiers
class ManageCashiersPage extends StatefulWidget {
  const ManageCashiersPage({super.key});

  @override
  State<ManageCashiersPage> createState() => _ManageCashiersPageState();
}

class _ManageCashiersPageState extends State<ManageCashiersPage> {
  final _cashierRepo = CashierRepository(db);
  final _authRepo = AuthRepository(db);
  List<User> _cashiers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCashiers();
  }

  Future<void> _loadCashiers() async {
    setState(() => _isLoading = true);
    
    try {
      final cashiers = await _cashierRepo.getAllCashiers();
      setState(() {
        _cashiers = cashiers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading cashiers: $e')),
      );
    }
  }

  Future<void> _showRegenerateRecoveryCodeDialog() async {
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Recovery Code'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your current PIN to generate a new recovery code.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Current PIN',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'PIN is required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              try {
                final result = await _authRepo.regenerateOwnerRecoveryCode(
                  pinController.text,
                );

                if (context.mounted) {
                  if (result.isSuccess && result.newRecoveryCode != null) {
                    Navigator.pop(context, result.newRecoveryCode);
                  } else {
                    Navigator.pop(context, null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.message ?? 'Incorrect PIN'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context, null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      // Navigate to save recovery code page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaveRecoveryCodePage(
            recoveryCode: result,
            onComplete: () {
              Navigator.pop(context);
            },
          ),
        ),
      );
    }
  }

  Future<void> _showAddCashierDialog() async {
    final usernameController = TextEditingController();
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Cashier'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Username is required'
                    : v.trim().length < 3
                        ? 'Minimum 3 characters'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'PIN (4-6 digits)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => v == null || v.length < 4 || v.length > 6
                    ? 'PIN must be 4-6 digits'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    v != pinController.text ? 'PINs do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              try {
                await _cashierRepo.createCashier(
                  username: usernameController.text.trim(),
                  pin: pinController.text,
                );

                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadCashiers();
    }
  }

  Future<void> _toggleCashierStatus(User cashier) async {
    try {
      await _cashierRepo.toggleCashierStatus(cashier.id, !cashier.isActive);
      _loadCashiers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cashier.isActive
                ? 'Cashier deactivated'
                : 'Cashier activated',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _openPermissionsPage(User cashier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPermissionsPage(user: cashier),
      ),
    );
  }

  Future<void> _showChangePinDialog(User cashier) async {
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final primaryColor = Theme.of(context).colorScheme.primary;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),

                        // Header icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.lock_reset_rounded,
                            color: primaryColor,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ganti PIN',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                            children: [
                              const TextSpan(text: 'Masukkan PIN baru untuk '),
                              TextSpan(
                                text: cashier.username,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // New PIN field
                        _buildPinField(
                          controller: newPinController,
                          label: 'PIN Baru',
                          hint: 'Masukkan 4-6 digit',
                          icon: Icons.lock_outline_rounded,
                          primaryColor: primaryColor,
                          validator: (v) => v == null || v.length < 4 || v.length > 6
                              ? 'PIN harus 4-6 digit'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Confirm PIN field
                        _buildPinField(
                          controller: confirmPinController,
                          label: 'Konfirmasi PIN',
                          hint: 'Ulangi PIN baru',
                          icon: Icons.lock_rounded,
                          primaryColor: primaryColor,
                          validator: (v) =>
                              v != newPinController.text ? 'PIN tidak cocok' : null,
                        ),
                        const SizedBox(height: 8),

                        // Info hint
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber.shade800),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'PIN harus terdiri dari 4 sampai 6 digit angka',
                                  style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey.shade700,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Batal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;

                                  try {
                                    await _cashierRepo.resetCashierPin(
                                      cashier.id,
                                      newPinController.text,
                                    );

                                    if (context.mounted) {
                                      Navigator.pop(context, true);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red.shade600,
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text('Simpan PIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('PIN berhasil diubah untuk ${cashier.username}')),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color primaryColor,
    required String? Function(String?) validator,
  }) {
    bool obscure = true;
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              obscureText: obscure,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(fontSize: 16, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400, letterSpacing: 0),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: primaryColor, size: 20),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 1.5),
                ),
              ),
              validator: validator,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Cashiers'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Regenerate Recovery Code',
            onPressed: _showRegenerateRecoveryCodeDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cashiers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No cashiers yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add a cashier',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _cashiers.length,
                  itemBuilder: (context, index) {
                    final cashier = _cashiers[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cashier.isActive
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            color: cashier.isActive
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          cashier.username,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cashier.isActive
                                ? null
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        subtitle: Text(
                          cashier.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: cashier.isActive
                                ? Colors.green
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Change PIN button
                            IconButton(
                              icon: const Icon(Icons.password),
                              tooltip: 'Change PIN',
                              onPressed: () => _showChangePinDialog(cashier),
                            ),
                            
                            // Permissions button
                            IconButton(
                              icon: const Icon(Icons.security),
                              tooltip: 'Permissions',
                              onPressed: () => _openPermissionsPage(cashier),
                            ),
                            
                            // Toggle active/inactive
                            Switch(
                              value: cashier.isActive,
                              onChanged: (_) => _toggleCashierStatus(cashier),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCashierDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Cashier'),
      ),
    );
  }
}
