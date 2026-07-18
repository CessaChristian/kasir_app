import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/app_database.dart';
import '../../data/business_context.dart';

/// Logo business dengan urutan prioritas:
/// 1. File dari `logo_path` (di-set owner via page Business)
/// 2. Asset bawaan Teras Inn (khusus business bernama "Teras Inn")
/// 3. Icon default sesuai tipe business (garpu dine-in / gelas grab-and-go)
class BusinessLogo extends StatelessWidget {
  /// Business yang ditampilkan. Null = business aktif saat ini.
  final BusinessesData? business;
  final double size;

  const BusinessLogo({super.key, this.business, required this.size});

  @override
  Widget build(BuildContext context) {
    final biz = business ?? BusinessContext.instance.activeBusiness;
    final path = biz?.logoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.15),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (biz == null || biz.name.trim().toLowerCase() == 'teras inn') {
      return Image.asset(
        'assets/images/Logo Teras Inn.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, e, s) => _fallbackIcon(context, biz),
      );
    }
    return _fallbackIcon(context, biz);
  }

  Widget _fallbackIcon(BuildContext context, BusinessesData? biz) {
    return Icon(
      biz?.type == 'beverage_grabandgo'
          ? Icons.local_cafe_rounded
          : Icons.restaurant_rounded,
      size: size * 0.6,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
