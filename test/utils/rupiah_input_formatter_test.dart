import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/currency_formatter.dart';

/// Isian uang (harga produk, uang diterima, pengeluaran, kas awal).
void main() {
  TextEditingValue isi(String teks, [int? kursor]) => TextEditingValue(
    text: teks,
    selection: TextSelection.collapsed(offset: kursor ?? teks.length),
  );

  TextEditingValue ketik(
    String lama,
    String baru, {
    int? kursor,
    int maksDigit = 9,
  }) => RupiahInputFormatter(
    maksDigit: maksDigit,
  ).formatEditUpdate(isi(lama), isi(baru, kursor));

  test('titik ribuan disusun ulang setiap ketikan', () {
    expect(ketik('', '5').text, '5');
    expect(ketik('1.000', '1.0005').text, '10.005');
    expect(ketik('', '007').text, '7');
    expect(ketik('5', '').text, '');
  });

  test('lebih dari batas digit: ketikan diabaikan, bukan jadi 0', () {
    final hasil = ketik('123.456.789', '123.456.7890');
    expect(hasil.text, '123.456.789');

    // Dulu 20 digit tidak muat di int dan diam-diam jadi "0".
    expect(ketik('', '12345678901234567890').text, '');
    expect(ketik('5.000', '12345678901234567890').text, '5.000');
  });

  test('batas digit bisa diatur per isian', () {
    expect(
      ketik('123.456.789', '1.234.567.890', maksDigit: 10).text,
      '1.234.567.890',
    );
  });

  test('tempelan berdesimal dibaca tanpa sen', () {
    expect(ketik('', '50.000,00').text, '50.000');
    expect(ketik('', '50000,5').text, '50.000');
    expect(ketik('', 'Rp 25.000').text, '25.000');
  });

  test('kursor tetap di tempat ketikan, tidak melompat ke ujung', () {
    // "1|0.000" lalu ketik 5 → "15|0.000".
    final sisip = ketik('10.000', '150.000', kursor: 2);
    expect(sisip.text, '150.000');
    expect(sisip.selection.baseOffset, 2);

    // "100.|000" lalu hapus titik-nya lewat backspace angka kiri → "10|.000".
    final hapus = ketik('100.000', '10.000', kursor: 2);
    expect(hapus.text, '10.000');
    expect(hapus.selection.baseOffset, 2);

    expect(ketik('1.000', '1.0005').selection.baseOffset, '10.005'.length);
  });
}
