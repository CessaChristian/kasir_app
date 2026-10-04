import 'dart:async';

import 'package:flutter/foundation.dart';

import '../supabase/supabase_service.dart';
import 'kemajuan_sync.dart';
import 'sync_engine.dart';
import 'sync_service.dart';

/// Berapa lama layar menunggu sinkron TERSAMBUNG (keputusan owner
/// 2026-10-04): lewat dari ini tanpa satu pun laporan kemajuan, pengguna
/// diberi tahu gagal dan layar dilepas.
const batasTersambung = Duration(seconds: 5);

/// Jalankan sinkron, tapi jangan biarkan layar menunggu lebih dari
/// [batas] kalau sinkronnya belum tersambung sama sekali.
///
/// "Tersambung" = sudah ada laporan kemajuan (data mulai ditarik/dikirim).
/// Sinkron yang sudah tersambung dibiarkan selesai walau lewat [batas] —
/// HP baru yang menarik ribuan baris memang butuh waktu, dan memutusnya
/// membuat datanya tidak pernah lengkap.
///
/// Kalau waktunya habis, hasilnya gagal-karena-jaringan. Putaran sinkron di
/// belakang TIDAK dibatalkan: ia tetap dibatasi [batasPermintaan] per
/// permintaan, dan kalau ternyata berhasil, datanya tetap tersimpan.
Future<HasilSync> sinkronBerbatas({
  Future<HasilSync> Function()? jalankan,
  ValueListenable<KemajuanSync?>? kemajuan,
  Duration batas = batasTersambung,
}) {
  final proses = (jalankan ?? SyncService.instance.jalankan)();
  final laporan = kemajuan ?? SyncService.instance.kemajuan;
  final hasil = Completer<HasilSync>();

  final pengawas = Timer(batas, () {
    if (!hasil.isCompleted && laporan.value == null) {
      hasil.complete(
        const HasilSync(
          error: 'tidak tersambung ke server',
          sebabTerputus: SebabTerputus.jaringan,
        ),
      );
    }
  });

  proses.then(
    (h) {
      pengawas.cancel();
      if (!hasil.isCompleted) hasil.complete(h);
    },
    onError: (Object e) {
      pengawas.cancel();
      if (!hasil.isCompleted) {
        hasil.complete(
          HasilSync(error: '$e', sebabTerputus: SebabTerputus.jaringan),
        );
      }
    },
  );

  return hasil.future;
}
