import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Kolom isian di lembar (desain Kelola Kasir): label di atas, kotak bertepi
/// berikon, dan [akhiran] opsional di kanan (ikon mata, centang cocok).
/// [galat] memerahkan tepinya.
class KolomLembar extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? ikon;

  /// Teks tetap di depan isian, mis. "@" untuk username.
  final String? awalan;
  final String? petunjuk;
  final bool sembunyikan;
  final bool galat;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final Widget? akhiran;
  final bool autofocus;

  const KolomLembar({
    super.key,
    required this.label,
    required this.controller,
    this.ikon,
    this.awalan,
    this.petunjuk,
    this.sembunyikan = false,
    this.galat = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.akhiran,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: TeksTeras.kecil,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A5048),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: galat ? WarnaTeras.merah : const Color(0xFFBDB6AF),
            ),
          ),
          child: Row(
            children: [
              if (ikon != null) ...[
                Icon(ikon, size: 21, color: WarnaTeras.oranye),
                const SizedBox(width: 10),
              ],
              if (awalan != null) ...[
                Text(
                  awalan!,
                  style: const TextStyle(
                    fontSize: TeksTeras.menu,
                    color: WarnaTeras.teksSamar,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: sembunyikan,
                  autofocus: autofocus,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                    fontSize: TeksTeras.menu,
                    letterSpacing: sembunyikan ? 4 : 0,
                    color: WarnaTeras.teks,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: petunjuk,
                    hintStyle: const TextStyle(
                      color: Color(0xFFB5ADA6),
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              ?akhiran,
            ],
          ),
        ),
      ],
    );
  }
}
