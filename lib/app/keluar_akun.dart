import 'package:flutter/material.dart';

import '../data/db.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../shared/auth/session_manager.dart';
import '../shared/ui/lembar_konfirmasi.dart';
import '../shared/widgets/app_toast.dart';

/// Tanya dulu, lalu keluar dari akun dan kembali ke layar login.
///
/// Dipakai tombol Keluar di Profil owner dan Profil kasir.
Future<void> keluarDariAkun(BuildContext context) async {
  // Lembar konfirmasi desain ("Keluar dari akun?"). Catatannya tetap
  // membedakan kasir yang shiftnya masih berjalan.
  final adaShift = SessionManager.instance.currentSession?.shiftId != null;
  final confirmed = await tampilkanLembarKonfirmasi(
    context,
    ikon: Icons.logout_rounded,
    judul: 'Keluar dari akun?',
    catatan: adaShift
        ? 'Shift Anda masih aktif. Shift tetap berjalan dan bisa dilanjutkan '
              'setelah masuk lagi.'
        : 'Kamu perlu masuk lagi dengan username dan PIN untuk memakai '
              'aplikasi.',
    labelAksi: 'Keluar',
  );

  if (!confirmed) return;

  try {
    // Sengaja TIDAK menutup shift — lihat AuthRepository.logout.
    if (SessionManager.instance.currentSession != null) {
      await AuthRepository(db).logout();
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
