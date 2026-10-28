import 'package:flutter/services.dart';

/// Format angka ke format rupiah (tanpa simbol Rp)
/// Contoh: 1000000 -> "1.000.000"
String formatRupiah(int value) {
  final str = value.toString();
  final result = StringBuffer();
  int count = 0;

  for (int i = str.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) {
      result.write('.');
    }
    result.write(str[i]);
    count++;
  }

  return result.toString().split('').reversed.join();
}

/// Parse string rupiah ke int
/// Contoh: "1.000.000" -> 1000000
int? parseRupiah(String value) {
  final cleaned = value.replaceAll('.', '').replaceAll(',', '').trim();
  return int.tryParse(cleaned);
}

/// TextInputFormatter untuk isian uang dengan titik ribuan otomatis.
///
/// Sudah menyaring sendiri semua yang bukan angka, jadi JANGAN dipasang
/// bersama `FilteringTextInputFormatter.digitsOnly`: penyaring itu membuang
/// koma desimal sebelum formatter ini sempat melihatnya.
///
/// - Paling banyak [maksDigit] angka. Ketikan yang melebihi diabaikan (angka
///   lama tetap). Dulu tidak dibatasi, dan 19–20 digit tidak muat di `int`
///   sehingga harganya diam-diam jadi Rp 0.
/// - Tempelan berdesimal ("50.000,00") dibaca 50.000, bukan 5.000.000.
/// - Kursor tetap di tempat yang diketik, tidak melompat ke ujung.
class RupiahInputFormatter extends TextInputFormatter {
  final int maksDigit;

  RupiahInputFormatter({this.maksDigit = 9});

  /// Sen di ujung tempelan: ",5" atau ",00". Formatter ini sendiri tidak
  /// pernah menulis koma, jadi koma pasti datang dari luar.
  static final _desimal = RegExp(r',\d{1,2}$');
  static final _bukanAngka = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var teks = newValue.text;
    var kursor = newValue.selection.end.clamp(0, teks.length);
    final desimal = _desimal.firstMatch(teks);
    if (desimal != null) {
      teks = teks.substring(0, desimal.start);
      if (kursor > teks.length) kursor = teks.length;
    }

    final angka = teks.replaceAll(_bukanAngka, '');
    if (angka.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    // Panjang dicek SEBELUM diubah jadi angka: 19 digit ke atas tidak muat
    // di int.
    final tanpaNolDepan = angka.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (tanpaNolDepan.length > maksDigit) return oldValue;
    final nilai = int.parse(tanpaNolDepan);

    final hasil = formatRupiah(nilai);
    // Banyaknya angka di KANAN kursor tetap sama sesudah titik ribuan
    // disusun ulang.
    final angkaKanan = teks
        .substring(kursor)
        .replaceAll(_bukanAngka, '')
        .length
        .clamp(0, tanpaNolDepan.length);
    var posisi = hasil.length;
    for (var dilewati = 0; dilewati < angkaKanan; posisi--) {
      if (hasil[posisi - 1] != '.') dilewati++;
    }
    // Menempel ke angka terakhir yang diketik, bukan di belakang titik.
    while (posisi > 0 && hasil[posisi - 1] == '.') {
      posisi--;
    }
    return TextEditingValue(
      text: hasil,
      selection: TextSelection.collapsed(offset: posisi),
    );
  }
}

/// Format lengkap dengan simbol, mis. 1250000 -> "Rp 1.250.000" dan
/// -5000 -> "-Rp 5.000". [formatRupiah] sendiri tidak menangani angka
/// negatif (hasilnya "-.100"), padahal laba kotor bisa minus.
String formatRp(int value) =>
    value < 0 ? '-Rp ${formatRupiah(-value)}' : 'Rp ${formatRupiah(value)}';

/// Format nominal di baris Riwayat (desain): 12000 -> "Rp. 12.000,00".
String formatRpRiwayat(int value) => 'Rp. ${formatRupiah(value)},00';
