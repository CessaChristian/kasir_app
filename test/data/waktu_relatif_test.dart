import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/perangkat/perangkat_repository.dart';

/// Halaman Perangkat dipakai pemilik untuk memutuskan HP mana yang dicabut.
/// Keputusan itu bersandar pada "terakhir aktif", jadi kalimatnya harus
/// terbaca sekilas dan tidak pernah menyesatkan.
void main() {
  final kini = DateTime(2026, 9, 25, 12, 0);
  String hasil(Duration lalu) =>
      waktuRelatif(kini.subtract(lalu), sekarang: kini);

  test('di bawah semenit disebut baru saja', () {
    expect(hasil(const Duration(seconds: 0)), 'baru saja');
    expect(hasil(const Duration(seconds: 59)), 'baru saja');
  });

  test('menit, jam, hari', () {
    expect(hasil(const Duration(minutes: 2)), '2 menit lalu');
    expect(hasil(const Duration(minutes: 59)), '59 menit lalu');
    expect(hasil(const Duration(hours: 3)), '3 jam lalu');
    expect(hasil(const Duration(hours: 23)), '23 jam lalu');
    expect(hasil(const Duration(days: 5)), '5 hari lalu');
  });

  test('bulan dan tahun', () {
    expect(hasil(const Duration(days: 45)), '1 bulan lalu');
    expect(hasil(const Duration(days: 400)), '1 tahun lalu');
  });

  test('jam perangkat yang melenceng ke depan tidak jadi angka negatif', () {
    // Jam HP bisa saja lebih lambat dari jam server. "-3 menit lalu" akan
    // terbaca seperti kerusakan, padahal artinya cuma "barusan".
    expect(hasil(const Duration(minutes: -5)), 'baru saja');
  });
}
