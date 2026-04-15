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

/// TextInputFormatter untuk input harga dengan format rupiah otomatis
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Hapus semua karakter non-digit
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final value = int.tryParse(digitsOnly) ?? 0;
    final formatted = formatRupiah(value);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
