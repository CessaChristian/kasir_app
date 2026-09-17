import 'package:flutter/material.dart';

import '../../data/sync/sync_service.dart';
import 'alasan_terputus.dart';
import 'app_toast.dart';
import 'dialog_sync.dart';

/// Menyimpan perubahan lalu MENGIRIMNYA, dan melaporkan keadaan yang
/// sebenarnya terjadi.
///
/// ── MASALAH YANG DIPECAHKAN ──
///
/// Semua tindakan pemilik dulu hanya menulis ke database lokal lalu langsung
/// berkata "berhasil". Perubahannya memang tidak hilang — barisnya mengantre
/// dengan `sync_status = 'pending'` dan pasti terkirim — tapi baru naik di
/// putaran otomatis berikutnya, sampai lima menit kemudian.
///
/// Untuk tindakan yang akibatnya dirasakan di HP LAIN, jeda itu membingungkan
/// dan kadang berbahaya:
///
/// - kasir baru dibuat  -> kasirnya belum bisa login sama sekali
/// - PIN kasir direset  -> kasirnya terkunci, PIN baru belum sampai
/// - kasir dinonaktifkan -> orang yang aksesnya dicabut masih bisa berjualan
///
/// Pemilik tidak punya cara tahu sudah sampai atau belum, dan pesan "berhasil"
/// membuatnya menganggap selesai.
///
/// ── KENAPA DITUNGGU, BUKAN DILEPAS ──
///
/// Hasil pengiriman ditunggu supaya pesan yang muncul menyatakan keadaan
/// SEBENARNYA, bukan menebak. Menampilkan "terkirim" tanpa memastikan sama
/// menyesatkannya dengan yang lama.
///
/// ── KENAPA SATU PEMBANTU, BUKAN DISALIN ──
///
/// Empat tempat memakai alur yang sama persis. Empat salinan pasti berbeda
/// halus cepat atau lambat — dan project ini sudah pernah menanggung
/// akibatnya, saat dua fungsi izin yang seharusnya sama menjawab dari sumber
/// berbeda dan membuat tombol tidak muncul tanpa penjelasan.
///
/// Mengembalikan true kalau penyimpanannya berhasil — TERLEPAS dari
/// terkirim atau tidak. Kegagalan mengirim bukan kegagalan menyimpan.
Future<bool> simpanLaluKirim(
  BuildContext context, {
  required Future<void> Function() simpan,
  required String pesanTerkirim,
  required String pesanTertunda,
  String Function(Object galat)? pesanGagal,
}) async {
  try {
    await simpan();
  } catch (e) {
    if (context.mounted) {
      AppToast.error(
        context,
        pesanGagal?.call(e) ?? 'Gagal menyimpan: $e',
      );
    }
    return false;
  }

  if (!context.mounted) return true;

  await kirimSekarang(
    context,
    pesanTerkirim: pesanTerkirim,
    pesanTertunda: pesanTertunda,
  );
  return true;
}

/// Mengirim perubahan yang BARU SAJA disimpan, lalu melaporkan keadaannya.
///
/// Bentuk terpisah karena sebagian penyimpanan terjadi di dalam dialog yang
/// menutup dirinya sendiri — di sana penyimpanan dan pengiriman tidak bisa
/// dibungkus jadi satu panggilan. Isinya tetap satu tempat supaya tidak ada
/// dua versi aturan "kapan disebut terkirim".
Future<void> kirimSekarang(
  BuildContext context, {
  required String pesanTerkirim,
  required String pesanTertunda,
}) async {
  final hasil = await DialogSync.tampilkanSelama(
    context,
    SyncService.instance.jalankan,
  );

  if (!context.mounted) return;

  if (hasil.berhasil) {
    AppToast.success(context, pesanTerkirim);
    return;
  }

  // SENGAJA tidak disebut gagal. Perubahannya sudah tersimpan dan pasti
  // terkirim begitu jaringan kembali; menyebutnya gagal justru membuat
  // pemilik mengulang hal yang sudah berhasil.
  //
  // Kecuali perangkatnya ditolak server: di situ "akan terkirim saat online"
  // adalah janji yang tidak akan ditepati, karena HP ini sudah online.
  final alasan = alasanTakPulihSendiri(hasil.sebabTerputus);
  AppToast.warning(
    context,
    alasan == null ? pesanTertunda : 'Tersimpan, tapi belum terkirim — $alasan',
  );
}
