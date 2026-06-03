import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';

/// Widget error state standar dengan tombol Muat Ulang.
/// Gunakan di semua StreamBuilder/FutureBuilder snapshot.hasError.
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback onRetry;
  final IconData icon;
  final double iconSize;

  const ErrorStateWidget({
    super.key,
    required this.onRetry,
    this.title = 'Gagal memuat data',
    this.message = 'Terjadi kesalahan saat mengambil data.',
    this.icon = Icons.cloud_off_rounded,
    this.iconSize = 52,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: Colors.grey.shade300),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Muat Ulang'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl, vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
