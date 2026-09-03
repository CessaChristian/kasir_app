import 'dart:io';

import '../../../shared/services/image_storage_service.dart';
import 'package:flutter/material.dart';
import '../../../data/app_database.dart';
import '../../../utils/currency_formatter.dart';

/// Product card/tile widget
class ProductTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ProductTile({
    super.key,
    required this.product,
    required this.categoryName,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Product Image / Icon
                _buildThumbnail(primaryColor),
                const SizedBox(width: 14),
                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rp ${formatRupiah(product.price)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Badges row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Category Badge
                          _buildBadge(
                            icon: Icons.category_outlined,
                            label: categoryName,
                          ),
                          // Stock Badge
                          // Barcode Badge
                          if (product.barcode != null && product.barcode!.isNotEmpty)
                            _buildBadge(
                              icon: Icons.qr_code_rounded,
                              label: product.barcode!,
                            ),
                          // Spicy Badge
                          if (product.hasSpicyOption)
                            _buildBadge(
                              icon: Icons.local_fire_department_rounded,
                              label: 'Ada pilihan pedas',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Menu Button
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.grey.shade500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade700),
                          const SizedBox(width: 12),
                          const Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Hapus', style: TextStyle(color: Colors.red)),
                        ],
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
  }
  
  Widget _buildThumbnail(Color primaryColor) {
    // Database menyimpan path RELATIF sejak v15; diresolusi ke path absolut
    // lewat ImageStorageService (path absolut lama tetap dilayani).
    final path = product.imagePath;
    final hasImage = ImageStorageService.adaSync(path);

    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(ImageStorageService.lokasiPenuhSync(path!)),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, err, stack) => _defaultIcon(primaryColor),
        ),
      );
    }
    return _defaultIcon(primaryColor);
  }

  Widget _defaultIcon(Color primaryColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
    );
  }

  Widget _buildBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
}
