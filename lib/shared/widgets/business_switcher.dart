import 'package:flutter/material.dart';
import '../../data/business_context.dart';

/// Label nama business aktif di app bar — STATIS, tidak bisa di-tap.
/// Ganti business hanya lewat page Business (drawer, owner-only) dengan
/// dialog konfirmasi (spec REVISI 2, D6).
class BusinessSwitcher extends StatelessWidget {
  const BusinessSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BusinessContext.instance,
      builder: (context, _) {
        final business = BusinessContext.instance.activeBusiness;
        if (business == null) return const SizedBox.shrink();
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
      },
    );
  }
}
