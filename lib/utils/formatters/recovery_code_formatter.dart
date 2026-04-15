import 'package:flutter/services.dart';

/// Custom formatter untuk recovery code input
/// 
/// Auto-format menjadi XXXX-XXXX-XXXX-XXXX
/// Contoh: ABCDEFGH → ABCD-EFGH
class RecoveryCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Get text without dashes
    final text = newValue.text.replaceAll('-', '').toUpperCase();
    
    // Max 16 characters
    if (text.length > 16) {
      return oldValue;
    }

    // Build formatted string
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      
      // Add dash after every 4 characters (except at the end)
      if ((i + 1) % 4 == 0 && i + 1 != text.length) {
        buffer.write('-');
      }
    }

    final formatted = buffer.toString();
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
