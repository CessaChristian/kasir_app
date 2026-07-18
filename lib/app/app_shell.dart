import 'package:flutter/material.dart';
import '../shared/widgets/app_toast.dart';
import '../features/dashboard/pages/dashboard_page.dart';
import '../features/products/pages/products_page.dart';
import '../features/sales/sales_page.dart';
import '../features/history/history_page.dart';
import '../features/report/report_page.dart';
import '../features/owner/pages/manage_cashiers_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../data/db.dart';
import '../data/app_database.dart';
import '../data/business_context.dart';
import '../shared/constants/app_constants.dart';
import '../shared/auth/session_manager.dart';
import '../shared/widgets/business_switcher.dart';
import '../features/settings/pages/device_mode_page.dart';
import '../features/settings/pages/business_settings_page.dart';
import '../features/onboarding/widgets/business_setup_step.dart';
import '../features/onboarding/repositories/onboarding_repository.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<AppShellState> globalKey = GlobalKey<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  // Cache stream agar tidak dibuat ulang setiap build() dipanggil.
  // Diperbarui saat BusinessContext ganti business aktif.
  Stream<List<Product>> _productStream = const Stream.empty();

  @override
  void initState() {
    super.initState();
    _productStream = db.watchProducts();
    BusinessContext.instance.addListener(_onBusinessChanged);
  }

  void _onBusinessChanged() {
    setState(() => _productStream = db.watchProducts());
  }

  @override
  void dispose() {
    BusinessContext.instance.removeListener(_onBusinessChanged);
    super.dispose();
  }

  void navigateToPage(int index) {
    setState(() => _selectedIndex = index);
  }

  // Navigasi berdasarkan label agar aman saat menu di-filter per permission.
  void navigateToPageByLabel(String label) {
    final idx = _availableMenuItems.indexWhere((item) => item['label'] == label);
    if (idx >= 0) setState(() => _selectedIndex = idx);
  }

  final _allMenuItems = const [
    {
      'icon': Icons.dashboard_rounded,
      'label': 'Dashboard',
      'permission': 'all',
      'page': DashboardPage(),
    },
    {
      'icon': Icons.inventory_2_rounded,
      'label': 'Produk',
      'permission': 'manage_products',
      'page': ProductsPage(),
    },
    {
      'icon': Icons.point_of_sale_rounded,
      'label': 'Kasir',
      'permission': 'create_transaction',
      'page': SalesPage(),
    },
    {
      'icon': Icons.receipt_long_rounded,
      'label': 'Riwayat',
      'permission': 'view_history',
      'page': HistoryPage(),
    },
    {
      'icon': Icons.analytics_rounded,
      'label': 'Laporan',
      'permission': 'view_report',
      'page': ReportPage(),
    },
    {
      'icon': Icons.account_balance_wallet_rounded,
      'label': 'Pengeluaran',
      'permission': 'all',
      'page': ExpensesPage(),
    },
  ];

  List<Map<String, dynamic>> get _availableMenuItems {
    return _allMenuItems.where((item) {
      final permission = item['permission'] as String;
      if (permission == 'all') return true;
      return SessionManager.instance.hasPermission(permission);
    }).toList();
  }

  void _navigateTo(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
  }

  Future<void> _logout() async {
    Navigator.pop(context); // Close drawer first

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Keluar dari Sistem?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 8),
              Text(
                'Anda akan mengakhiri sesi dan keluar dari aplikasi',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
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
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final session = SessionManager.instance.currentSession;
      if (session != null) {
        final authRepo = AuthRepository(db);
        await authRepo.logout(userId: session.userId, shiftId: session.shiftId);
      }

      await SessionManager.instance.clearSession();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Gagal keluar: $e');
    }
  }

  Future<void> _showAddBusinessSheet(BuildContext ctx) async {
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: BusinessSetupStep(
          onBack: () => Navigator.pop(ctx),
          onSubmit: ({required name, required type, address, phone}) async {
            Navigator.pop(ctx);
            try {
              final userId = SessionManager.instance.currentUserId!;
              final repo = OnboardingRepository();
              final bizId = await repo.addBusinessToOwner(
                userId: userId,
                businessName: name,
                businessType: type,
                businessAddress: address,
                businessPhone: phone,
              );
              // Switch ke business baru
              await BusinessContext.instance.switchTo(bizId, userId: userId);
              await SessionManager.instance.refreshRoleCache();
              if (mounted) {
                AppToast.success(context, 'Business "$name" berhasil dibuat');
              }
            } catch (e) {
              if (mounted) {
                AppToast.error(context, 'Gagal membuat business: $e');
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildDrawerMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Colors.red.shade50
                        : (isSelected
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: isDestructive
                        ? Colors.red.shade400
                        : (isSelected ? colorScheme.primary : Colors.grey.shade600),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isDestructive
                          ? Colors.red.shade400
                          : (isSelected ? colorScheme.primary : const Color(0xFF2A2A2A)),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = SessionManager.instance.currentSession;
    final availableItems = _availableMenuItems;

    if (_selectedIndex >= availableItems.length) {
      _selectedIndex = 0;
    }

    // Dashboard (index 0) tidak butuh AppBar — DashboardPage punya headernya sendiri
    final isDashboard = _selectedIndex == 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Jika tidak di dashboard, kembali ke dashboard
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
        // Jika sudah di dashboard, tidak lakukan apa-apa (jangan keluar app)
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: isDashboard
          ? null
          : AppBar(
              title: const BusinessSwitcher(),
              centerTitle: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.black.withValues(alpha: 0.06),
              scrolledUnderElevation: 1,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  color: Colors.grey.shade700,
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            ),

      // ── Drawer ──
      drawer: Drawer(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drawer Header ──
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(24)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo + Store Name
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/images/Logo Teras Inn.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, e, s) => Icon(
                                  Icons.restaurant_rounded,
                                  size: 28,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ListenableBuilder(
                            listenable: BusinessContext.instance,
                            builder: (_, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  BusinessContext.instance.activeBusiness?.name ??
                                      AppConstants.storeName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                Text(
                                  'POS Sistem',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                    letterSpacing: 2.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Divider(color: Colors.grey.shade100, height: 1),
                      const SizedBox(height: 16),

                      // User info card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5F0),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                session?.isOwner == true
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.person_rounded,
                                color: colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session?.username ?? 'User',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      session?.isOwner == true ? 'Owner' : 'Kasir',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Menu Items ──
            Expanded(
              child: Container(
                color: const Color(0xFFF8F5F0),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  children: [
                    Text(
                      'MENU',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade400,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    for (int i = 0; i < availableItems.length; i++)
                      _buildDrawerMenuItem(
                        context,
                        icon: availableItems[i]['icon'] as IconData,
                        label: availableItems[i]['label'] as String,
                        isSelected: i == _selectedIndex,
                        onTap: () => _navigateTo(i),
                      ),

                    // Owner-only section
                    if (SessionManager.instance.hasPermission('manage_cashiers')) ...[
                      const SizedBox(height: 12),
                      Divider(color: Colors.grey.shade300, height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'MANAJEMEN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade400,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDrawerMenuItem(
                        context,
                        icon: Icons.people_rounded,
                        label: 'Kelola Kasir',
                        isSelected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ManageCashiersPage()),
                          );
                        },
                      ),
                      if (SessionManager.instance.hasCurrentPermission('manage_business')) ...[
                        _buildDrawerMenuItem(
                          context,
                          icon: Icons.storefront_rounded,
                          label: 'Pengaturan Business',
                          isSelected: false,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BusinessSettingsPage()),
                            );
                          },
                        ),
                        _buildDrawerMenuItem(
                          context,
                          icon: Icons.add_business_rounded,
                          label: 'Tambah Business',
                          isSelected: false,
                          onTap: () {
                            Navigator.pop(context);
                            _showAddBusinessSheet(context);
                          },
                        ),
                        _buildDrawerMenuItem(
                          context,
                          icon: Icons.devices_rounded,
                          label: 'Mode Device',
                          isSelected: false,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DeviceModePage()),
                            );
                          },
                        ),
                      ],
                      // "Laporan Shift" dipindah jadi tab "Shift" di halaman
                      // Laporan — menghilangkan kebingungan dua menu laporan.
                    ],

                    const SizedBox(height: 8),

                    // Low stock warning
                    if (SessionManager.instance.hasPermission('manage_products'))
                      StreamBuilder<List<Product>>(
                        stream: _productStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return const SizedBox.shrink();
                          final products = snapshot.data ?? [];
                          final lowStockCount = products
                              .where((p) =>
                                  p.trackStock && (p.stock ?? 0) <= AppConstants.lowStockThreshold)
                              .length;
                          if (lowStockCount == 0) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange.shade400, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$lowStockCount produk stok menipis',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                  ),
                ),
              ),
            ),

            // ── Logout ──
            Container(
              color: const Color(0xFFF8F5F0),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Column(
                children: [
                  Divider(color: Colors.grey.shade300, height: 1),
                  const SizedBox(height: 8),
                  _buildDrawerMenuItem(
                    context,
                    icon: Icons.logout_rounded,
                    label: 'Keluar',
                    isSelected: false,
                    isDestructive: true,
                    onTap: _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      body: availableItems.isNotEmpty
          ? availableItems[_selectedIndex]['page'] as Widget
          : const Center(child: Text('Tidak ada akses')),
      ),
    );
  }
}
