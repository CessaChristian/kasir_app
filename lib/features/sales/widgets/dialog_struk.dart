import 'package:flutter/material.dart';

import '../../../data/app_database.dart';
import '../../../data/nama_tercatat.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/isi_struk.dart';
import '../repositories/sales_repository.dart';

/// Struk sesudah pembayaran (desain): isi struk lalu [Cetak Struk]
/// [Selesai]. Tidak bisa ditutup dengan mengetuk luar — kasir menekan
/// Selesai setelah menyerahkan kembalian.
Future<void> tampilkanStrukSesudahBayar(
  BuildContext context, {
  required String transaksiId,
  required SalesRepository repo,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DialogStruk(transaksiId: transaksiId, repo: repo),
);

class _DialogStruk extends StatefulWidget {
  final String transaksiId;
  final SalesRepository repo;

  const _DialogStruk({required this.transaksiId, required this.repo});

  @override
  State<_DialogStruk> createState() => _DialogStrukState();
}

class _DialogStrukState extends State<_DialogStruk> {
  Transaction? _tx;
  List<TransactionItem>? _items;
  String? _namaKasir;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final tx = await widget.repo.ambilTransaksi(widget.transaksiId);
    if (tx == null) return;
    final items = await widget.repo.getTransactionItems(tx.id);
    final nama = await widget.repo.namaAkun();
    if (!mounted) return;
    setState(() {
      _tx = tx;
      _items = items;
      _namaKasir = tx.namaKasir(nama);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = _tx;
    return Dialog(
      backgroundColor: WarnaTeras.kartu,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: tx == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: IsiStruk(
                        transaksi: tx,
                        items: _items,
                        namaKasir: _namaKasir,
                        latar: WarnaTeras.kartu,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TombolLembar(
                            label: 'Cetak Struk',
                            latar: WarnaTeras.oranye,
                            warna: Colors.white,
                            tinggi: 42,
                            sudut: 6,
                            // Fitur printer belum dibuat. Tombolnya tetap
                            // tampil sesuai desain, tapi belum melakukan
                            // apa-apa (keputusan owner 2026-10-13).
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TombolLembar(
                            label: 'Selesai',
                            latar: WarnaTeras.oranye,
                            warna: Colors.white,
                            tinggi: 42,
                            sudut: 6,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
