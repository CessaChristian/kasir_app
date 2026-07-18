import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../data/business_context.dart';
import '../../../data/db.dart';
import '../../../shared/auth/session_manager.dart';
import '../../../shared/widgets/business_logo.dart';
import 'business_detail_page.dart';

/// Page "Business" (owner-only): daftar business milik owner.
/// Business di-hardcode dari kode (spec REVISI 2) — tidak ada tombol tambah.
/// Tap item → detail (edit alamat/telepon/logo + aktivasi business).
class BusinessListPage extends StatefulWidget {
  const BusinessListPage({super.key});

  @override
  State<BusinessListPage> createState() => _BusinessListPageState();
}

class _BusinessListPageState extends State<BusinessListPage> {
  List<BusinessesData> _businesses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SessionManager.instance.currentUserId;
    if (userId == null) return;
    final rows = await (db.select(db.businesses).join([
      innerJoin(
        db.userBusinessRoles,
        db.userBusinessRoles.businessId.equalsExp(db.businesses.id) &
            db.userBusinessRoles.userId.equals(userId) &
            db.userBusinessRoles.deletedAt.isNull(),
      ),
    ])
          ..where(db.businesses.deletedAt.isNull() &
              db.businesses.isActive.equals(true)))
        .get();
    if (!mounted) return;
    setState(() {
      _businesses = rows.map((r) => r.readTable(db.businesses)).toList();
      _loading = false;
    });
  }

  String _typeLabel(String type) => type == 'beverage_grabandgo'
      ? 'Beverage Grab-and-Go'
      : 'Restaurant Dine-in';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeId = BusinessContext.instance.activeBusinessId;

    return Scaffold(
      appBar: AppBar(title: const Text('Business')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _businesses.length,
              separatorBuilder: (_, i) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final b = _businesses[i];
                final isActive = b.id == activeId;
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BusinessDetailPage(businessId: b.id),
                        ),
                      );
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color:
                                  colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: BusinessLogo(business: b, size: 44),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _typeLabel(b.type),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Aktif',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            )
                          else
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
