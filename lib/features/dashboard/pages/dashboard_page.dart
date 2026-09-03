import 'package:flutter/material.dart';
import '../../../shared/widgets/business_logo.dart';
import 'package:intl/intl.dart';
import '../../../app/app_shell.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/widgets/sync_refresh.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../data/db.dart';
import '../../shift/repositories/shift_repository.dart';
import '../../../features/auth/pages/login_page.dart';
import '../../../features/auth/repositories/auth_repository.dart';
import '../widgets/active_shift_card.dart';
import '../widgets/owner_shift_shortcut_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Pagi';
    if (hour < 15) return 'Siang';
    if (hour < 18) return 'Sore';
    return 'Malam';
  }

  Future<void> _showEndShiftDialog(BuildContext context) async {
    final session = SessionManager.instance.currentSession;
    if (session == null) return;

    // Owner tidak menjalankan shift (shiftId null) → ini murni "Keluar".
    final shiftId = session.shiftId;
    final hasShift = shiftId != null;

    final revenue = hasShift ? await ShiftRepository(db).getShiftRevenue(shiftId) : 0;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    if (!context.mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

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
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    color: colorScheme.primary,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                hasShift ? 'Akhiri Shift?' : 'Keluar dari Sistem?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasShift
                    ? 'Anda akan mengakhiri shift dan keluar dari sistem'
                    : 'Anda akan keluar dari aplikasi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (hasShift) Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          color: colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Total Pendapatan Shift',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: revenue.toDouble()),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, child) => Text(
                        formatter.format(v.toInt()),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
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
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            hasShift ? 'Akhiri' : 'Keluar',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
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

    if (confirmed != true || !context.mounted) return;

    // Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(hasShift ? 'Mengakhiri shift...' : 'Keluar...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final authRepo = AuthRepository(db);
      await authRepo.logout(userId: session.userId, shiftId: shiftId);
      await SessionManager.instance.clearSession();

      if (!context.mounted) return;
      Navigator.pop(context); // close loading
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // close loading
      AppToast.error(context, 'Gagal mengakhiri shift: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionManager.instance.currentSession;
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dayName = DateFormat('EEEE', 'id_ID').format(now);
    final dateStr = DateFormat('d MMM yyyy', 'id_ID').format(now);
    // Role, BUKAN permission. Dulu baris ini memakai
    // hasPermission('manage_cashiers') sebagai proksi role — akibatnya kasir
    // yang diberi izin kelola kasir ikut dianggap owner, lalu kehilangan
    // kartu shift aktifnya sendiri. Lihat test/arsitektur/role_bukan_permission_test.dart
    final isOwner = SessionManager.instance.isOwner;

    final menuItems = [
      {
        'icon': Icons.inventory_2_rounded,
        'label': 'Produk',
        'description': 'Kelola produk & kategori',
        'permission': 'manage_products',
      },
      {
        'icon': Icons.point_of_sale_rounded,
        'label': 'Kasir',
        'description': 'Buat transaksi baru',
        'permission': 'create_transaction',
      },
      {
        'icon': Icons.receipt_long_rounded,
        'label': 'Riwayat',
        'description': 'Lihat riwayat transaksi',
        'permission': 'view_history',
      },
      {
        'icon': Icons.analytics_rounded,
        'label': 'Laporan',
        'description': 'Analisis penjualan',
        'permission': 'view_report',
      },
      {
        'icon': Icons.account_balance_wallet_rounded,
        'label': 'Pengeluaran',
        'description': 'Catat pengeluaran shift',
        'permission': 'all',
      },
    ];

    final availableMenuItems = menuItems.where((item) {
      final p = item['permission'] as String;
      if (p == 'all') return true;
      return SessionManager.instance.hasPermission(p);
    }).toList();

    // DashboardPage tidak pakai Scaffold sendiri — cukup pakai AppShell punya
    // Builder diperlukan agar Scaffold.of(context) menemukan AppShell Scaffold
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // ── Header Card ──
          Container(
            width: double.infinity,
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
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar: menu | logo | spacer | user chip
                    Row(
                      children: [
                        // Menu button (opens AppShell drawer)
                        Builder(
                          builder: (ctx) => IconButton(
                            icon: Icon(
                              Icons.menu_rounded,
                              color: Colors.grey.shade700,
                            ),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),

                        // Logo
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: const BusinessLogo(size: 28),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      AppConstants.storeName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'POS Sistem',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade400,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Date + day
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Greeting + user chip
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selamat ${_getGreeting()},',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  session?.username ?? 'User',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // User chip — tap to end shift
                          GestureDetector(
                            onTap: () => _showEndShiftDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isOwner
                                        ? Icons.admin_panel_settings_rounded
                                        : Icons.person_rounded,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    session?.shiftId == null
                                        ? 'Keluar'
                                        : 'Akhiri Shift',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
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

          // ── Scrollable Content ──
          Expanded(
            child: Stack(
              children: [
                // Layer 1: konten scroll
                SyncRefresh(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Owner: pintasan pantau shift kasir (owner tidak punya
                        // shift). Cashier: kartu shift aktif miliknya.
                        if (isOwner)
                          const OwnerShiftShortcutCard()
                        else
                          const ActiveShiftCard(),
                        const SizedBox(height: 20),

                        // Quick access
                        _buildSectionLabel('Akses Cepat', colorScheme.primary),
                        const SizedBox(height: 12),

                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.05,
                              ),
                          itemCount: availableMenuItems.length,
                          itemBuilder: (ctx, i) {
                            final item = availableMenuItems[i];
                            return _buildFeatureCard(
                              ctx,
                              icon: item['icon'] as IconData,
                              label: item['label'] as String,
                              description: item['description'] as String,
                              primaryColor: colorScheme.primary,
                              delay: i * 60,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title, Color primaryColor) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required Color primaryColor,
    required int delay,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(0, 16 * (1 - v)),
        child: Opacity(opacity: v, child: child),
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () =>
              AppShell.globalKey.currentState?.navigateToPageByLabel(label),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: primaryColor),
                ),
                const Spacer(),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
