import 'package:flutter/material.dart';
import '../../../data/app_database.dart';
import '../category_manager.dart';

/// Horizontal category filter bar widget
class CategoryFilterBar extends StatelessWidget {
  final String? selectedCategoryId;
  final List<Category> categories;
  final ValueChanged<String?> onCategorySelected;

  const CategoryFilterBar({
    super.key,
    required this.selectedCategoryId,
    required this.categories,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // "Semua" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Semua'),
              selected: selectedCategoryId == null,
              onSelected: (_) => onCategorySelected(null),
              avatar: selectedCategoryId == null
                  ? const Icon(Icons.check, size: 18)
                  : const Icon(Icons.apps, size: 18),
            ),
          ),
          // Category chips
          ...categories.map((c) {
            final isSelected = selectedCategoryId == c.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: isSelected,
                onSelected: (_) => onCategorySelected(c.id),
                avatar: isSelected
                    ? const Icon(Icons.check, size: 18)
                    : const Icon(Icons.category_outlined, size: 18),
              ),
            );
          }),
          // Manage categories button
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              label: const Text('Kelola'),
              avatar: const Icon(Icons.settings, size: 18),
              onPressed: () => CategoryManager.show(context),
              side: BorderSide(color: colorScheme.outline),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
