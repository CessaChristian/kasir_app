import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Isian bertepi dengan ikon oranye di kiri; labelnya mengecil ke atas
/// begitu terisi (desain form produk).
class KolomIsian extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData ikon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  const KolomIsian({
    super.key,
    required this.controller,
    required this.label,
    required this.ikon,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.prefixText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCFC8C1)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(ikon, size: 21, color: WarnaTeras.oranye),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              textInputAction: textInputAction,
              onChanged: onChanged,
              style: const TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w500,
                color: WarnaTeras.teks,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: WarnaTeras.teksSamar),
                floatingLabelStyle: const TextStyle(
                  color: WarnaTeras.teksPudar,
                  fontSize: TeksTeras.kecil,
                ),
                prefixText: prefixText,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak bertepi yang membuka pilihan (mis. Kategori): ikon · label kecil ·
/// nilai · panah bawah.
class KolomPilihan extends StatelessWidget {
  final IconData ikon;
  final String label;
  final String nilai;
  final bool kosong;
  final VoidCallback onTap;

  const KolomPilihan({
    super.key,
    required this.ikon,
    required this.label,
    required this.nilai,
    required this.onTap,
    this.kosong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 54,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCFC8C1)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(ikon, size: 21, color: WarnaTeras.oranye),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                    Text(
                      nilai,
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w500,
                        color: kosong ? WarnaTeras.teksSamar : WarnaTeras.teks,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 24,
                color: WarnaTeras.teksPudar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
