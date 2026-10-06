import 'package:flutter/material.dart';
import '../shared/widgets/app_toast.dart';
import '../features/dashboard/pages/dashboard_page.dart';
import '../features/products/pages/products_page.dart';
import '../features/sales/sales_page.dart';
import '../features/history/history_page.dart';
import '../features/report/pages/laporan_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/auth/pages/login_page.dart';
import '../shared/constants/app_constants.dart';
import '../shared/auth/session_manager.dart';
import '../shared/widgets/business_logo.dart';
import '../features/shift/pages/riwayat_shift_page.dart';
import 'kerangka_owner.dart';
import 'keluar_akun.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<AppShellState> globalKey = GlobalKey<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _selectedIndex = 0;


  @override
  void initState() {
    super.initState();
    // Menu drawer dan Akses Cepat disaring berdasarkan izin. Tanpa mendengar
    // ini, izin yang baru turun dari server baru terlihat setelah pengguna
    // keluar dan masuk lagi.
    SessionManager.instance.sesiBerubah.addListener(_sesiBerubah);
    SessionManager.instance.sesiDicabut.addListener(_sesiDicabut);
  }

  /// Sesi dicabut dari jarak jauh — pemilik menonaktifkan atau menghapus akun
  /// ini, dan sinkronisasi baru saja membawa kabarnya.
  ///
  /// Dipaksa keluar, bukan sekadar diberi peringatan: selama masih di dalam
  /// aplikasi, orang yang aksesnya sudah dicabut tetap bisa membuat transaksi.
  ///
  /// Keranjang yang sedang disusun ikut hilang. Itu disengaja — penonaktifan
  /// adalah tindakan sengaja dan jarang, dan menundanya sampai transaksi
  /// selesai membuka jendela di mana orang yang sudah dicabut masih berjualan.
  /// Kalau ternyata salah pencet, pemilik tinggal mengaktifkan lagi; yang
  /// hilang cuma input, bukan data yang sudah tersimpan.
  void _sesiDicabut() {
    final alasan = SessionManager.instance.sesiDicabut.value;
    if (alasan == null || !mounted) return;
    SessionManager.instance.tandaiPencabutanSudahDitangani();

    AppToast.warning(context, alasan);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _sesiBerubah() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionManager.instance.sesiBerubah.removeListener(_sesiBerubah);
    SessionManager.instance.sesiDicabut.removeListener(_sesiDicabut);
    super.dispose();
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
      // Hak semua akun. Izin `view_history` mengatur SEJAUH APA ke belakang
      // isinya, bukan boleh-tidaknya membuka — lihat `CakupanRiwayat`.
      'permission': 'all',
      'page': HistoryPage(),
    },
    {
      'icon': Icons.analytics_rounded,
      'label': 'Laporan',
      'permission': 'view_report',
      'page': LaporanPage(),
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
    // Owner sudah memakai UI baru (nav bawah). Drawer di bawah ini tinggal
    // milik kasir sampai lapisan kasir dimigrasi. Role, BUKAN permission —
    // lihat test/arsitektur/role_bukan_permission_test.dart
    if (SessionManager.instance.isOwner) return const KerangkaOwner();

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isDashboard
          ? null
          : AppBar(
              title: const Text(
                AppConstants.storeName,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
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
                              child: const BusinessLogo(size: 40),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
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
                        ],
                      ),

                      const SizedBox(height: 16),
                      Divider(color: Colors.grey.shade100, height: 1),
                      const SizedBox(height: 16),

                      // User info card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
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
                                Icons.person_rounded,
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
                                      'Kasir',
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
                color: Theme.of(context).scaffoldBackgroundColor,
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

                    // Pantau Shift — hak semua akun. Isinya dibatasi izin
                    // `view_all_shifts`: tanpa itu hanya shift sendiri.
                    _buildDrawerMenuItem(
                        context,
                        icon: Icons.monitor_heart_outlined,
                        label: 'Pantau Shift',
                        isSelected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RiwayatShiftPage()),
                          );
                        },
                      ),

                    const SizedBox(height: 8),
                  ],
                  ),
                ),
              ),
            ),

            // ── Logout ──
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
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
                    onTap: () {
                      Navigator.pop(context); // tutup drawer dulu
                      keluarDariAkun(context);
                    },
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
