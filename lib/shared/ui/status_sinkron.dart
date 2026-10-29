import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sync/sync_otomatis.dart';
import '../../data/sync/sync_service.dart';
import 'teks_teras.dart';
import 'warna_teras.dart';

/// "Sinkron terakhir 14:32".
String labelSinkronTerakhir(DateTime? waktu, DateTime sekarang) {
  if (waktu == null) return 'Belum pernah sinkron';
  final jam = DateFormat('HH:mm').format(waktu);
  final hariIni =
      waktu.year == sekarang.year &&
      waktu.month == sekarang.month &&
      waktu.day == sekarang.day;
  return hariIni
      ? 'Sinkron terakhir $jam'
      : 'Sinkron terakhir ${DateFormat('d MMM', 'id_ID').format(waktu)} $jam';
}

/// Peringatan sinkron, atau null kalau semuanya normal.
///
/// - Ada baris HP ini yang ditolak server ([SyncService.jumlahGagalKirim]).
/// - Ada baris server yang tertahan di HP ini (lihat `BarisTertahan`):
///   biasanya karena aplikasinya belum diperbarui.
/// - Sinkron belum berhasil lebih dari [SyncOtomatis.batasBasi]: data di HP
///   ini — stok harga, open bill dari HP lain, laporan — mungkin sudah basi.
///
/// Dulu kegagalan sinkron otomatis sepenuhnya diam. Satu-satunya tanda adalah
/// tulisan kecil abu-abu ini, yang tidak berubah walau sudah berhari-hari.
String? peringatanSinkron({
  required int tertahan,
  int gagalKirim = 0,
  required DateTime? terakhirBerhasil,
  required DateTime sekarang,
}) {
  // Paling dulu: data yang hanya ada di HP ini (QA kedua S10). Owner juga
  // melihatnya di Daftar Perangkat.
  if (gagalKirim > 0) {
    return '$gagalKirim data dari HP ini ditolak server dan belum terkirim. '
        'Beri tahu owner.';
  }
  if (tertahan > 0) {
    return '$tertahan data dari server belum bisa disimpan di HP ini. '
        'Perbarui aplikasi ke versi terbaru.';
  }
  final basi =
      terakhirBerhasil == null ||
      sekarang.difference(terakhirBerhasil) > SyncOtomatis.batasBasi;
  if (!basi) return null;
  return '${labelSinkronTerakhir(terakhirBerhasil, sekarang)} — data di HP '
      'ini mungkin belum terbaru. Periksa internet lalu tarik layar untuk '
      'menyegarkan.';
}

/// Label "Sinkron terakhir …" yang berubah jadi peringatan oranye lewat
/// [peringatanSinkron].
class StatusSinkron extends StatefulWidget {
  /// Hanya tampil kalau ada peringatan (Dashboard owner).
  final bool hanyaPeringatan;

  const StatusSinkron({super.key, this.hanyaPeringatan = false});

  @override
  State<StatusSinkron> createState() => _StatusSinkronState();
}

class _StatusSinkronState extends State<StatusSinkron> {
  late final Timer _detak;

  @override
  void initState() {
    super.initState();
    // "Basi" bergantung pada jam, bukan hanya pada kejadian: tanpa detak ini
    // labelnya tidak pernah berubah oranye selama tidak ada sinkron baru.
    _detak = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _detak.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sync.jumlahTertahan,
        sync.jumlahGagalKirim,
        sync.terakhirBerhasil,
      ]),
      builder: (context, _) {
        final waktu = sync.terakhirBerhasil.value;
        final sekarang = DateTime.now();
        final pesan = peringatanSinkron(
          tertahan: sync.jumlahTertahan.value,
          gagalKirim: sync.jumlahGagalKirim.value,
          terakhirBerhasil: waktu,
          sekarang: sekarang,
        );
        if (pesan != null) return _peringatan(pesan);
        if (widget.hanyaPeringatan) return const SizedBox.shrink();
        return Row(
          children: [
            const Icon(
              Icons.update_rounded,
              size: 15,
              color: WarnaTeras.teksPudar,
            ),
            const SizedBox(width: 5),
            Text(
              labelSinkronTerakhir(waktu, sekarang),
              style: const TextStyle(fontSize: 12, color: WarnaTeras.teksPudar),
            ),
          ],
        );
      },
    );
  }

  Widget _peringatan(String pesan) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E6),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF6C894)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.sync_problem_rounded,
          size: 20,
          color: WarnaTeras.oranye,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pesan,
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              height: 1.35,
              color: WarnaTeras.teks,
            ),
          ),
        ),
      ],
    ),
  );
}
