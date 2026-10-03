/// Sapaan sesuai jam, untuk "Selamat ___," di dashboard.
String sapaanWaktu(DateTime waktu) {
  final jam = waktu.hour;
  if (jam < 12) return 'Pagi';
  if (jam < 15) return 'Siang';
  if (jam < 18) return 'Sore';
  return 'Malam';
}
