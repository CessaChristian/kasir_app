import 'package:intl/intl.dart';

/// "2j 15m" — lama shift berjalan. Sehari atau lebih: "8 hari 1 jam" —
/// dulu "193j 7m", susah dibaca untuk shift yang lupa ditutup (audit 6 Nov
/// nomor 49).
String lamaShift(DateTime mulai, DateTime sekarang) {
  final d = sekarang.difference(mulai);
  if (d.isNegative) return '0m';
  final jam = d.inHours;
  final menit = d.inMinutes % 60;
  if (d.inDays >= 1) {
    final sisaJam = jam % 24;
    return sisaJam == 0
        ? '${d.inDays} hari'
        : '${d.inDays} hari $sisaJam jam';
  }
  return jam == 0 ? '${menit}m' : '${jam}j ${menit}m';
}

/// "08:00", atau "Sen 5 Nov 08:00" kalau bukan hari ini.
String jamMulaiShift(DateTime mulai, DateTime sekarang) {
  final jam = DateFormat('HH:mm').format(mulai);
  final hariIni =
      mulai.year == sekarang.year &&
      mulai.month == sekarang.month &&
      mulai.day == sekarang.day;
  if (hariIni) return jam;
  return '${DateFormat('E d MMM', 'id_ID').format(mulai)} $jam';
}

/// "13:26–21:04", atau "1 Okt 13:26–21:04" kalau bukan hari ini. Shift
/// yang melewati tengah malam menulis tanggal selesainya: "20:39–3 Okt
/// 18:55" — tanpa itu jam selesai tampak lebih awal dari jam mulai.
String rentangShift(DateTime mulai, DateTime? selesai, DateTime sekarang) {
  final jam = DateFormat('HH:mm');
  final hariIni =
      mulai.year == sekarang.year &&
      mulai.month == sekarang.month &&
      mulai.day == sekarang.day;
  final awal = hariIni
      ? jam.format(mulai)
      : '${DateFormat('d MMM', 'id_ID').format(mulai)} ${jam.format(mulai)}';
  if (selesai == null) return '$awal–sekarang';
  final hariSama =
      selesai.year == mulai.year &&
      selesai.month == mulai.month &&
      selesai.day == mulai.day;
  final akhir = hariSama
      ? jam.format(selesai)
      : '${DateFormat('d MMM', 'id_ID').format(selesai)} ${jam.format(selesai)}';
  return '$awal–$akhir';
}
