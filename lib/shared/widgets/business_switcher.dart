import 'package:flutter/material.dart';
import '../../data/business_context.dart';
import '../../shared/auth/session_manager.dart';

/// Dropdown di app bar yang tampil nama business aktif.
/// Hanya visible kalau:
/// - User adalah owner (has 'switch_business' permission), DAN
/// - Ada lebih dari 1 business yang bisa diakses
///
/// Tap → bottom sheet daftar business.
class BusinessSwitcher extends StatelessWidget {
  const BusinessSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    // Cek permission
    final canSwitch =
        SessionManager.instance.hasCurrentPermission('switch_business');

    return ListenableBuilder(
      listenable: BusinessContext.instance,
      builder: (context2, _) {
        final ctx = BusinessContext.instance;
        if (!ctx.isReady) return const SizedBox.shrink();

        final business = ctx.activeBusiness!;

        // Kalau hanya 1 business atau tidak punya permission → tampilkan nama saja (no tap)
        if (!canSwitch || !ctx.hasMultipleBusinesses) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              business.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        // Multi-business + owner → tappable
        return InkWell(
          onTap: () => _showSwitcherSheet(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSwitcherSheet(BuildContext context) {
    final ctx = BusinessContext.instance;
    final session = SessionManager.instance;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Pilih Business',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ...ctx.availableBusinesses.map((b) {
              final isActive = b.id == ctx.activeBusinessId;
              return ListTile(
                leading: Icon(
                  b.type == 'restaurant_dinein'
                      ? Icons.restaurant_rounded
                      : Icons.local_cafe_rounded,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(b.name),
                subtitle: Text(
                  b.type == 'restaurant_dinein'
                      ? 'Restaurant Dine-in'
                      : 'Beverage Grab-and-Go',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: isActive
                    ? Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: isActive
                    ? null
                    : () async {
                        Navigator.pop(context);
                        final userId = session.currentUserId!;
                        await BusinessContext.instance.switchTo(
                          b.id,
                          userId: userId,
                        );
                        await session.refreshRoleCache();
                      },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
