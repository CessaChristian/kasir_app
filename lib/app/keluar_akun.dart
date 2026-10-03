import 'package:flutter/material.dart';

import '../data/db.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../shared/auth/session_manager.dart';
import '../shared/widgets/app_toast.dart';

/// Tanya dulu, lalu keluar dari akun dan kembali ke layar login.
///
/// Dipakai menu Keluar di drawer kasir dan di Profil owner.
Future<void> keluarDariAkun(BuildContext context) async {
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Keluar dari Sistem?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            Text(
              SessionManager.instance.currentSession?.shiftId == null
                  ? 'Anda akan keluar dari aplikasi'
                  : 'Anda keluar dari akun, tapi SHIFT TETAP BERJALAN. '
                      'Untuk menutup shift, pakai tombol Akhiri Shift di '
                      'halaman utama.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
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
                    child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.w600)),
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

  try {
    final session = SessionManager.instance.currentSession;
    if (session != null) {
      final authRepo = AuthRepository(db);
      // Sengaja TIDAK menutup shift. Ini tombol "Keluar", bukan
      // "Akhiri Shift" — kasir yang cuma meminjam HP rekan harus bisa
      // menyerahkannya kembali tanpa mematikan shift yang masih
      // berjalan di HP-nya sendiri.
      await authRepo.logout(
        userId: session.userId,
        shiftId: session.shiftId,
        akhiriShift: false,
      );
    }

    await SessionManager.instance.clearSession();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  } catch (e) {
    if (!context.mounted) return;
    AppToast.error(context, 'Gagal keluar: $e');
  }
}
