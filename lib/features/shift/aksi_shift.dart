import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../shared/auth/session_manager.dart';
import '../../shared/ui/dialog_memuat.dart';
import '../../shared/ui/dialog_tengah.dart';
import '../../shared/ui/warna_teras.dart';
import '../../shared/widgets/app_toast.dart';
import '../../utils/currency_formatter.dart';
import '../open_bill/repositories/open_bill_repository.dart';
import 'pengelola_shift.dart';
import 'repositories/shift_repository.dart';
import 'widgets/dialog_buka_shift.dart';
import '../../utils/pesan_galat.dart';

String _pesanGalat(Object e) => e is IzinDitolak
    ? 'Akun ini tidak punya izin Buka & Tutup Shift'
    : pesanGalat(e);

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
/// Semua yang perlu ditanyakan ke server — open bill dari HP lain dan
/// perangkat lain yang masih memegang shift — diperiksa SEKALIGUS di balik
/// kartu "Memeriksa shift…" sebelum dialog apa pun muncul. Dulu dialognya
/// baru muncul sesudah tarikan open bill selesai tanpa tanda apa pun, jadi
/// kasir mengetuk berulang dan dialognya muncul bertumpuk. Kartunya
/// dipasang pada ketukan itu juga, jadi ketukan berikutnya tertahan.
///
/// Masih ada open bill → "Shift belum bisa ditutup" (desain); tombol Lihat
/// Open Bill menjalankan [onLihatOpenBill]. Masih dipegang perangkat lain →
/// dialog yang sama dengan nama perangkatnya (dulu toast 2 detik yang tidak
/// sempat terbaca).
Future<void> tutupShiftLewatDialog(
  BuildContext context, {
  PengelolaShift? pengelola,
  ShiftRepository? repo,
  OpenBillRepository? repoBill,
  VoidCallback? onLihatOpenBill,
}) async {
  final shiftId = SessionManager.instance.currentSession?.shiftId;
  if (shiftId == null) return;
  final p = pengelola ?? PengelolaShift(db);
  final rb = repoBill ?? OpenBillRepository(db);
  final (jumlahBill, halangan, ringkasan) = await jalankanDenganMemuat(
    context,
    () => (
      // Bill dari HP lain di shift yang sama ikut terhitung.
      rb.segarkanDariServer().then((_) => rb.jumlahTerbuka(shiftId)),
      p.halanganMenutup(shiftId),
      (repo ?? ShiftRepository(db)).watchShift(shiftId).first,
    ).wait,
    pesan: 'Memeriksa shift…',
  );
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
  if (halangan != null) {
    await _tampilkanHalangan(context, halangan);
    return;
  }

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

  // Diperiksa ULANG: selama dialog terbuka, perangkat lain bisa saja baru
  // masuk ke shift ini.
  final Object? gagal;
  try {
    gagal = await jalankanDenganMemuat(context, () async {
      final h = await p.halanganMenutup(shiftId);
      if (h != null) return h;
      await p.tutup();
      return null;
    }, pesan: 'Menutup shift…');
  } catch (e) {
    if (context.mounted) AppToast.error(context, _pesanGalat(e));
    return;
  }
  if (!context.mounted) return;
  if (gagal is String) {
    await _tampilkanHalangan(context, gagal);
    return;
  }
  AppToast.success(context, 'Shift ditutup');
}

/// Alasan shift belum boleh ditutup — dialog, bukan toast: pesannya bisa
/// tiga kalimat (nama perangkat, sisa menit), terlalu panjang untuk dibaca
/// dalam dua detik.
Future<void> _tampilkanHalangan(BuildContext context, String alasan) =>
    tampilkanDialogTengah(
      context,
      ikon: Icons.devices_rounded,
      judul: 'Shift belum bisa ditutup',
      catatan: alasan,
      labelBatal: null,
      labelAksi: 'Mengerti',
      warnaAksi: WarnaTeras.oranye,
      latarIkon: WarnaTeras.oranyeMuda,
    );
