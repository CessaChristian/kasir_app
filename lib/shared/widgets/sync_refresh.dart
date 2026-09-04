import 'package:flutter/material.dart';

import '../../data/sync/sync_service.dart';
import 'app_toast.dart';
import 'dialog_sync.dart';

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
        final hasil = await DialogSync.tampilkanSelama(
          context,
          SyncService.instance.jalankan,
        );
        await sesudah?.call();
        if (!context.mounted) return;

        if (hasil.berhasil) {
          if (hasil.ditarik > 0) {
            AppToast.success(context, '${hasil.ditarik} data diperbarui');
          } else if (hasil.didorong > 0) {
            AppToast.success(context, '${hasil.didorong} data terkirim');
          } else {
            AppToast.info(context, 'Sudah yang terbaru');
          }
        } else {
          // Offline bukan kesalahan pengguna: transaksinya tetap tersimpan
          // dan akan terkirim sendiri saat jaringan kembali.
          AppToast.warning(context, 'Gagal menyegarkan — periksa koneksi');
        }
      },
      child: child,
    );
  }
}
