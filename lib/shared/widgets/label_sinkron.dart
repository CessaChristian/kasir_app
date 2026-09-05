import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sync/sync_otomatis.dart';
import '../../data/sync/sync_service.dart';

/// Menampilkan kapan data terakhir berhasil disinkronkan, dan mengajak
/// menyegarkan kalau sudah basi.
///
/// ── KENAPA INI ADA ──
///
/// Kegagalan sinkronisasi tidak menimbulkan apa pun di layar. Aplikasi tetap
/// menampilkan harga lama dengan yakin, dan tidak ada yang menyadarinya sampai
/// ada pelanggan terlanjur dibayar dengan harga yang salah. Label ini mengubah
/// kegagalan senyap menjadi kegagalan yang kelihatan.
///
/// Saat datanya basi, teksnya berubah jadi ajakan menarik layar. Itu jauh
/// lebih dapat diandalkan daripada meminta pemilik mengingatkan kasir setiap
/// kali mengubah harga: peringatannya muncul di depan kasir tepat pada saat
/// dan tempat ia dibutuhkan, tanpa bergantung siapa pun ingat.
class LabelSinkron extends StatefulWidget {
  const LabelSinkron({super.key});

  @override
  State<LabelSinkron> createState() => _LabelSinkronState();
}

class _LabelSinkronState extends State<LabelSinkron> {
  Timer? _detak;

  @override
  void initState() {
    super.initState();
    // Tanpa detak, tulisan "5 menit lalu" membeku selamanya sampai ada hal
    // lain yang kebetulan menggambar ulang layar.
    _detak = Timer.periodic(
        const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _detak?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: SyncService.instance.terakhirBerhasil,
      builder: (context, waktu, _) {
        final basi = waktu == null ||
            DateTime.now().difference(waktu) > SyncOtomatis.batasBasi;

        final warna = basi ? const Color(0xFFB26A00) : Colors.grey.shade500;
        final teks = waktu == null
            ? 'Belum pernah disinkronkan — tarik ke bawah untuk menyegarkan'
            : basi
                ? 'Data ${_jarak(waktu)} — tarik ke bawah untuk menyegarkan'
                : 'Terakhir disinkronkan ${DateFormat('HH:mm').format(waktu)}';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                basi ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                size: 13,
                color: warna,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  teks,
                  style: TextStyle(
                    fontSize: 11,
                    color: warna,
                    fontWeight: basi ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _jarak(DateTime waktu) {
    final selisih = DateTime.now().difference(waktu);
    if (selisih.inDays >= 1) return '${selisih.inDays} hari lalu';
    if (selisih.inHours >= 1) return '${selisih.inHours} jam lalu';
    return '${selisih.inMinutes} menit lalu';
  }
}
