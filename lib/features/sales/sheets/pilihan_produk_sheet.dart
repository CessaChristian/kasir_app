import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../models/pilihan_produk.dart';

/// Tanyakan pilihan produk (Pedas / Manis / Es) setiap kali produk yang punya
/// pilihan diketuk di halaman Kasir.
///
/// Mengembalikan catatan untuk item struk, atau null kalau kasir menutup
/// lembarnya — produk TIDAK dimasukkan ke keranjang.
Future<String?> tanyaPilihanProduk(BuildContext context, Product produk) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PilihanProdukSheet(produk: produk),
  );
}

class _PilihanProdukSheet extends StatefulWidget {
  final Product produk;
  const _PilihanProdukSheet({required this.produk});

  @override
  State<_PilihanProdukSheet> createState() => _PilihanProdukSheetState();
}

class _PilihanProdukSheetState extends State<_PilihanProdukSheet> {
  late final List<KelompokPilihan> _kelompok = kelompokUntuk(widget.produk);

  // Sudah tertanda pilihan bawaan — kasir cukup mengubah yang diminta.
  late final Map<KelompokPilihan, String> _pilihan = {
    for (final k in _kelompok) k: k.bawaan,
  };

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.produk.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            for (final k in _kelompok) ...[
              const SizedBox(height: 16),
              Text(
                k.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opsi in k.daftar)
                    ChoiceChip(
                      label: Text(opsi),
                      selected: _pilihan[k] == opsi,
                      selectedColor: primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _pilihan[k] == opsi
                            ? primary
                            : const Color(0xFF1A1A1A),
                        fontWeight: _pilihan[k] == opsi
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() => _pilihan[k] = opsi),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, catatanDari(_pilihan)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Tambah ke Keranjang',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
