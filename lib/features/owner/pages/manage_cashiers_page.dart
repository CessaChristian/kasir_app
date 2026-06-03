import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/db.dart';
import '../../../shared/widgets/watermark_background.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../data/app_database.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/recovery/pages/save_recovery_code_page.dart';
import '../repositories/cashier_repository.dart';
import '../../../shared/auth/session_manager.dart';
import 'user_permissions_page.dart';

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
    // S11: Defense-in-depth — pastikan hanya user dengan permission
    // manage_cashiers yang bisa render halaman ini. Drawer filter saja
    // tidak cukup karena page bisa dipanggil via direct navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        SessionManager.instance.requirePermission('manage_cashiers');
      } on StateError {
        if (mounted) Navigator.of(context).pop();
      }
    });
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
      AppToast.error(context, 'Gagal memuat data kasir: $e');
    }
  }

  Future<void> _showRegenerateRecoveryCodeDialog() async {
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.vpn_key_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 28),
                ),
                const SizedBox(height: 14),
                const Text('Perbarui Kode Recovery',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 6),
                Text(
                  'Masukkan PIN saat ini untuk membuat kode recovery baru.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                _buildInputField(
                  controller: pinController,
                  label: 'PIN Saat Ini',
                  hint: '• • • • • •',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                  isPin: true,
                  validator: (v) => v == null || v.isEmpty ? 'PIN wajib diisi' : null,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          try {
                            final res = await _authRepo.regenerateOwnerRecoveryCode(pinController.text);
                            if (ctx.mounted) {
                              if (res.isSuccess && res.newRecoveryCode != null) {
                                Navigator.pop(ctx, res.newRecoveryCode);
                              } else {
                                Navigator.pop(ctx, null);
                                if (mounted) AppToast.error(context, res.message ?? 'PIN salah');
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) Navigator.pop(ctx, null);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Buat Kode Baru', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaveRecoveryCodePage(
            recoveryCode: result,
            onComplete: (ctx) => Navigator.pop(ctx),
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

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.person_add_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 28),
                  ),
                  const SizedBox(height: 14),
                  const Text('Tambah Kasir Baru',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 6),
                  Text(
                    'Buat akun kasir baru untuk mengakses sistem.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 24),
                  _buildInputField(
                    controller: usernameController,
                    label: 'Username',
                    hint: 'Nama pengguna kasir',
                    icon: Icons.person_outline_rounded,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Username wajib diisi';
                      if (v.trim().length < 3) return 'Minimal 3 karakter';
                      if (v.trim().length > 30) return 'Maksimal 30 karakter';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildInputField(
                    controller: pinController,
                    label: 'PIN (4–6 digit)',
                    hint: '• • • • • •',
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    isPin: true,
                    validator: (v) => v == null || v.length < 4 || v.length > 6
                        ? 'PIN harus 4–6 digit'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _buildInputField(
                    controller: confirmPinController,
                    label: 'Konfirmasi PIN',
                    hint: '• • • • • •',
                    icon: Icons.lock_rounded,
                    obscure: true,
                    isPin: true,
                    validator: (v) => v != pinController.text ? 'PIN tidak cocok' : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              await _cashierRepo.createCashier(
                                username: usernameController.text.trim(),
                                pin: pinController.text,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              if (ctx.mounted) Navigator.pop(ctx, false);
                              if (mounted) AppToast.error(context, 'Gagal: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Buat Akun', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) _loadCashiers();
  }

  Future<void> _toggleCashierStatus(User cashier) async {
    final isDeactivating = cashier.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isDeactivating ? 'Nonaktifkan Kasir?' : 'Aktifkan Kasir?'),
        content: Text(
          isDeactivating
              ? '${cashier.username} tidak akan bisa login setelah dinonaktifkan.'
              : '${cashier.username} akan dapat login kembali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDeactivating ? Colors.orange.shade600 : Colors.green.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text(isDeactivating ? 'Nonaktifkan' : 'Aktifkan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _cashierRepo.toggleCashierStatus(cashier.id, !cashier.isActive);
      _loadCashiers();
      if (!mounted) return;
      if (cashier.isActive) {
        AppToast.warning(context, '${cashier.username} dinonaktifkan');
      } else {
        AppToast.success(context, '${cashier.username} diaktifkan');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal: $e');
    }
  }

  void _openPermissionsPage(User cashier) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserPermissionsPage(user: cashier)),
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.lock_reset_rounded, color: primaryColor, size: 28),
                  ),
                  const SizedBox(height: 14),
                  const Text('Ganti PIN',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 6),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      children: [
                        const TextSpan(text: 'Masukkan PIN baru untuk '),
                        TextSpan(
                          text: cashier.username,
                          style: TextStyle(fontWeight: FontWeight.w600, color: primaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildInputField(
                    controller: newPinController,
                    label: 'PIN Baru',
                    hint: '• • • • • •',
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    isPin: true,
                    validator: (v) => v == null || v.length < 4 || v.length > 6
                        ? 'PIN harus 4–6 digit'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _buildInputField(
                    controller: confirmPinController,
                    label: 'Konfirmasi PIN',
                    hint: '• • • • • •',
                    icon: Icons.lock_rounded,
                    obscure: true,
                    isPin: true,
                    validator: (v) => v != newPinController.text ? 'PIN tidak cocok' : null,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PIN harus terdiri dari 4 sampai 6 digit angka',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              await _cashierRepo.resetCashierPin(cashier.id, newPinController.text);
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              if (ctx.mounted) Navigator.pop(ctx, false);
                              if (mounted) AppToast.error(context, 'Gagal: $e');
                            }
                          },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Simpan PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      AppToast.success(context, 'PIN ${cashier.username} berhasil diubah');
    }
  }

  // Shared input field builder (matches auth page style)
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isPin = false,
    String? Function(String?)? validator,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return StatefulBuilder(
      builder: (ctx, setLocal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              obscureText: obscure,
              keyboardType: isPin ? TextInputType.number : TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: isPin
                  ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
                  : null,
              style: TextStyle(
                fontSize: isPin ? 20 : 15,
                letterSpacing: isPin ? 6 : 0,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: isPin ? 16 : 14,
                  letterSpacing: isPin ? 4 : 0,
                ),
                prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
                suffixIcon: isPin
                    ? IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.grey.shade400,
                          size: 20,
                        ),
                        onPressed: () => setLocal(() => obscure = !obscure),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: AppBar(
        title: const Text(
          'Kelola Kasir',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: Colors.grey.shade700),
        actions: [
          IconButton(
            icon: Icon(Icons.vpn_key_rounded, color: colorScheme.primary),
            tooltip: 'Perbarui Kode Recovery',
            onPressed: _showRegenerateRecoveryCodeDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCashierDialog,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: const Text('Tambah Kasir', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: WatermarkBackground(child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2))
          : _cashiers.isEmpty
              ? _buildEmptyState(colorScheme)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _cashiers.length,
                  itemBuilder: (context, index) {
                    return _buildCashierCard(_cashiers[index], colorScheme);
                  },
                ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded, size: 40, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          const Text(
            'Belum Ada Kasir',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap tombol + untuk menambah kasir baru',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildCashierCard(User cashier, ColorScheme colorScheme) {
    final isActive = cashier.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.person_rounded,
                color: isActive ? colorScheme.primary : Colors.grey.shade400,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cashier.username,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive ? Colors.green.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green.shade500 : Colors.grey.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isActive ? 'Aktif' : 'Nonaktif',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _actionIcon(
                  icon: Icons.lock_reset_rounded,
                  tooltip: 'Ganti PIN',
                  onTap: () => _showChangePinDialog(cashier),
                ),
                _actionIcon(
                  icon: Icons.security_rounded,
                  tooltip: 'Izin Akses',
                  onTap: () => _openPermissionsPage(cashier),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: isActive,
                    onChanged: (_) => _toggleCashierStatus(cashier),
                    activeThumbColor: colorScheme.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}
