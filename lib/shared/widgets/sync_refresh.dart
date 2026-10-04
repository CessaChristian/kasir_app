import 'package:flutter/material.dart';

import '../../data/sync/sinkron_berbatas.dart';
import 'alasan_terputus.dart';
import 'app_toast.dart';

/// Bungkus daftar apa pun supaya bisa disegarkan dengan menarik dari atas.
///
/// Sinkronisasi hanya berjalan sekali saat aplikasi dibuka. Perubahan yang
/// dibuat pemilik di HP-nya SETELAH itu tidak akan muncul di HP kasir sampai
/// aplikasinya ditutup-buka — hal pertama yang dikeluhkan saat menguji dua
/// perangkat. Widget ini memberi jalan keluar yang wajar bagi pengguna.
///
/// [child] wajib bisa di-scroll DAN memakai `AlwaysScrollableScrollPhysics`,
/// kalau tidak gerakan menariknya tidak akan terbaca saat isinya pendek.
class SyncRefresh extends StatelessWidget {
  final Widget child;

  /// Dipanggil setelah sinkron selesai, untuk memuat ulang tampilan yang
  /// tidak otomatis mendengarkan perubahan database.
  final Future<void> Function()? sesudah;

  const SyncRefresh({super.key, required this.child, this.sesudah});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        // Putaran RefreshIndicator sendiri jadi penanda proses; tidak ada
        // popup yang mengunci layar. Belum tersambung dalam 5 detik =
        // dilaporkan gagal (lihat sinkronBerbatas).
        final hasil = await sinkronBerbatas();
        await sesudah?.call();
        if (!context.mounted) return;

        if (hasil.berhasil) {
          // Sengaja `berubah`, BUKAN `diperiksa` — lihat catatan HasilSync.
          if (hasil.berubah > 0) {
            AppToast.success(context, '${hasil.berubah} data diperbarui');
          } else if (hasil.didorong > 0) {
            AppToast.success(context, '${hasil.didorong} data terkirim');
          } else {
            AppToast.info(context, 'Sudah yang terbaru');
          }
          return;
        }
        final p = pesanGagalSinkron(hasil);
        p.sebagian
            ? AppToast.warning(context, p.pesan)
            : AppToast.error(context, p.pesan);
      },
      child: child,
    );
  }
}
