import 'package:flutter/material.dart';
import '../features/dashboard/pages/dashboard_page.dart';
import '../features/products/pages/products_page.dart';
import '../features/sales/sales_page.dart';
import '../features/history/history_page.dart';
import '../features/report/report_page.dart';
import '../features/owner/pages/manage_cashiers_page.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../data/db.dart';
import '../data/app_database.dart';
import '../shared/constants/app_constants.dart';
import '../shared/auth/session_manager.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  
  // Global key for accessing AppShell state
  static final GlobalKey<AppShellState> globalKey = GlobalKey<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _selectedIndex = 0; // Will be updated based on available pages
  
  /// Navigate to a specific page by index
  void navigateToPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // All possible menu items with their permission requirements
  final _allMenuItems = const [
    {
      'icon': Icons.dashboard_rounded,
      'label': 'Dashboard',
      'permission': 'all', // Dashboard accessible to all users
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
  ];

  // Filtered menu items based on permissions
  List<Map<String, dynamic>> get _availableMenuItems {
    return _allMenuItems.where((item) {
      final permission = item['permission'] as String;
      // 'all' permission means accessible to everyone
      if (permission == 'all') return true;
      return SessionManager.instance.hasPermission(permission);
    }).toList();
  }

  void _navigateTo(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context); // Close drawer
  }

  Future<void> _logout() async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    // Confirm logout
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              const Text(
                'Akhiri Shift?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'Anda akan mengakhiri shift dan keluar dari sistem',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Keluar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
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

    // End shift and clear session
    try {
      final session = SessionManager.instance.currentSession;
      if (session != null) {
        final authRepo = AuthRepository(db);
        await authRepo.logout(
          userId: session.userId,
          shiftId: session.shiftId,
        );
      }

      await SessionManager.instance.clearSession();

      if (!mounted) return;

      // Navigate to login page
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error logging out: $e')),
      );
    }
  }
  
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? primaryColor.withValues(alpha:0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isDestructive 
                      ? Colors.red 
                      : (isSelected ? primaryColor : Colors.grey.shade600),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isDestructive 
                          ? Colors.red 
                          : (isSelected ? primaryColor : const Color(0xFF1A1A1A)),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(2),
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

    // Ensure selected index is valid
    if (_selectedIndex >= availableItems.length) {
      _selectedIndex = availableItems.isNotEmpty ? 0 : 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          availableItems.isNotEmpty
              ? availableItems[_selectedIndex]['label'] as String
              : 'POS App',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              // Header with user info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        session?.isOwner == true ? Icons.admin_panel_settings : Icons.person,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session?.username ?? 'User',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              session?.isOwner == true ? 'Owner' : 'Kasir',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Divider(color: Colors.grey.shade200, height: 1),
              const SizedBox(height: 8),
              
              // Menu Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    // Main menu items
                    for (int i = 0; i < availableItems.length; i++)
                      _buildMenuItem(
                        context,
                        icon: availableItems[i]['icon'] as IconData,
                        label: availableItems[i]['label'] as String,
                        isSelected: i == _selectedIndex,
                        onTap: () => _navigateTo(i),
                      ),
                    
                    // Manage Cashiers (Owner only)
                    if (SessionManager.instance.hasPermission('manage_cashiers')) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(color: Colors.grey.shade200),
                      ),
                      _buildMenuItem(
                        context,
                        icon: Icons.people_rounded,
                        label: 'Kelola Kasir',
                        isSelected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ManageCashiersPage(),
                            ),
                          );
                        },
                      ),
                    ],
                    
                    const SizedBox(height: 8),
                    
                    // Low Stock Warning
                    if (SessionManager.instance.hasPermission('manage_products'))
                      StreamBuilder<List<Product>>(
                        stream: db.watchProducts(),
                        builder: (context, snapshot) {
                          final products = snapshot.data ?? [];
                          final lowStockCount = products
                              .where((p) =>
                                  p.trackStock && (p.stock ?? 0) <= AppConstants.lowStockThreshold)
                              .length;

                          if (lowStockCount == 0) return const SizedBox.shrink();

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.red.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$lowStockCount produk stok menipis',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red.shade700,
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
              
              // Logout button at bottom
              Divider(color: Colors.grey.shade200, height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: _buildMenuItem(
                  context,
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  isSelected: false,
                  isDestructive: true,
                  onTap: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
      body: availableItems.isNotEmpty
          ? availableItems[_selectedIndex]['page'] as Widget
          : const Center(
              child: Text('No permissions assigned'),
            ),
    );
  }
}
