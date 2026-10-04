import 'package:flutter/material.dart';

import '../data/db.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../shared/auth/session_manager.dart';
import '../shared/ui/lembar_konfirmasi.dart';
import '../shared/widgets/app_toast.dart';

/// Tanya dulu, lalu keluar dari akun dan kembali ke layar login.
///
/// Dipakai menu Keluar di drawer kasir dan di Profil owner.
Future<void> keluarDariAkun(BuildContext context) async {
  // Lembar konfirmasi desain ("Keluar dari akun?"). Catatannya tetap
  // membedakan kasir yang shiftnya masih berjalan.
  final adaShift = SessionManager.instance.currentSession?.shiftId != null;
  final confirmed = await tampilkanLembarKonfirmasi(
    context,
    ikon: Icons.logout_rounded,
    judul: 'Keluar dari akun?',
    catatan: adaShift
        ? 'Kamu keluar dari akun, tapi SHIFT TETAP BERJALAN. Untuk menutup '
            'shift, pakai tombol Akhiri Shift di halaman utama.'
        : 'Kamu perlu masuk lagi dengan username dan PIN untuk memakai '
            'aplikasi.',
    labelAksi: 'Keluar',
  );

  if (!confirmed) return;

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
