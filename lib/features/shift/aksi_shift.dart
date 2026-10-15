import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/ui/dialog_tengah.dart';
import '../../shared/ui/warna_teras.dart';
import '../../shared/widgets/app_toast.dart';
import '../../utils/currency_formatter.dart';
import '../open_bill/repositories/open_bill_repository.dart';
import 'pengelola_shift.dart';
import 'repositories/shift_repository.dart';
import 'widgets/dialog_buka_shift.dart';

String _pesanGalat(Object e) {
  final pesan = e is StateError ? e.message : '$e';
  return pesan.startsWith('Permission required')
      ? 'Akun ini tidak punya izin Buka & Tutup Shift'
      : 'Gagal: $pesan';
}

/// "Buka shift": tanya kas awal, lalu buka. Dipakai Dashboard, Profil, dan
/// layar "Buka shift dulu".
Future<void> bukaShiftLewatDialog(
  BuildContext context, {
  PengelolaShift? pengelola,
}) async {
  final sesi = SessionManager.instance.currentSession;
  if (sesi == null) return;
  if (!SessionManager.instance.hasPermission('open_close_shift')) {
    AppToast.error(context, 'Akun ini tidak punya izin Buka & Tutup Shift');
    return;
  }
  final kasAwal = await tampilkanDialogBukaShift(context, nama: sesi.username);
  if (kasAwal == null || !context.mounted) return;
  try {
    final dilanjutkan = await (pengelola ?? PengelolaShift(db)).buka(kasAwal);
    if (!context.mounted) return;
    dilanjutkan
        ? AppToast.info(
            context,
            'Shift Anda masih berjalan di perangkat lain — dilanjutkan',
          )
        : AppToast.success(context, 'Shift dibuka · selamat bekerja');
  } catch (e) {
    if (context.mounted) AppToast.error(context, _pesanGalat(e));
  }
}

/// "Tutup shift sekarang?" (desain): ringkasan shift, lalu tutup kalau tidak
/// ada yang menghalangi. Kasir tetap masuk dan bisa membuka shift baru.
///
/// Masih ada open bill → "Shift belum bisa ditutup" (desain); tombol Lihat
/// Open Bill menjalankan [onLihatOpenBill].
Future<void> tutupShiftLewatDialog(
  BuildContext context, {
  PengelolaShift? pengelola,
  ShiftRepository? repo,
  OpenBillRepository? repoBill,
  VoidCallback? onLihatOpenBill,
}) async {
  final shiftId = SessionManager.instance.currentSession?.shiftId;
  if (shiftId == null) return;

  final rb = repoBill ?? OpenBillRepository(db);
  // Bill dari HP lain di shift yang sama ikut terhitung.
  await rb.segarkanDariServer();
  final jumlahBill = await rb.jumlahTerbuka(shiftId);
  if (!context.mounted) return;
  if (jumlahBill > 0) {
    final lihat = await tampilkanDialogTengah(
      context,
      ikon: Icons.receipt_long_rounded,
      judul: 'Shift belum bisa ditutup',
      catatan:
          'Masih ada $jumlahBill open bill yang belum dibayar. Selesaikan '
          'pembayaran atau hapus bill tersebut sebelum menutup shift.',
      labelBatal: 'Tutup',
      labelAksi: 'Lihat Open Bill',
      warnaAksi: WarnaTeras.oranye,
      latarIkon: WarnaTeras.oranyeMuda,
    );
    if (lihat) onLihatOpenBill?.call();
    return;
  }
  final ringkasan = await (repo ?? ShiftRepository(db))
      .watchShift(shiftId)
      .first;
  if (!context.mounted) return;

  final mulai = ringkasan == null
      ? ''
      : '${DateFormat('HH:mm').format(ringkasan.shift.startAt)} – sekarang · ';
  final isi = ringkasan == null
      ? ''
      : '${ringkasan.jumlahTransaksi} transaksi · '
            '${formatRp(ringkasan.pendapatan)}. ';
  final ya = await tampilkanDialogTengah(
    context,
    ikon: Icons.logout_rounded,
    judul: 'Tutup shift sekarang?',
    catatan:
        'Shift $mulai$isi'
        'Setelah ditutup, kasir tidak bisa membuat transaksi sampai shift '
        'dibuka lagi.',
    labelAksi: 'Tutup Shift',
  );
  if (!ya || !context.mounted) return;

  final p = pengelola ?? PengelolaShift(db);
  final halangan = await p.halanganMenutup(shiftId);
  if (!context.mounted) return;
  if (halangan != null) {
    AppToast.error(context, halangan);
    return;
  }
  try {
    await p.tutup();
    if (context.mounted) AppToast.success(context, 'Shift ditutup');
  } catch (e) {
    if (context.mounted) AppToast.error(context, _pesanGalat(e));
  }
}
