import 'package:flutter/material.dart';

import '../../../data/db.dart';
import '../../../shared/ui/tombol_berlencana.dart';
import '../../sales/models/keranjang.dart';
import '../repositories/open_bill_repository.dart';
import '../sheets/lembar_open_bill.dart';

/// Ikon nota di header Dashboard dan Kasir (desain) dengan jumlah open bill
/// terbuka di shift berjalan.
class TombolOpenBill extends StatefulWidget {
  final Keranjang keranjang;
  final String? shiftId;

  /// Diisi test; aplikasi memakai basis data utama.
  final OpenBillRepository? repo;

  const TombolOpenBill({
    super.key,
    required this.keranjang,
    required this.shiftId,
    this.repo,
  });

  @override
  State<TombolOpenBill> createState() => _TombolOpenBillState();
}

class _TombolOpenBillState extends State<TombolOpenBill> {
  late final _repo = widget.repo ?? OpenBillRepository(db);
  late var _aliran = _repo.watchTerbuka(widget.shiftId);

  @override
  void didUpdateWidget(TombolOpenBill lama) {
    super.didUpdateWidget(lama);
    if (lama.shiftId != widget.shiftId) {
      _aliran = _repo.watchTerbuka(widget.shiftId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _aliran,
      builder: (context, snap) => TombolBerlencana(
        ikon: Icons.receipt_long_rounded,
        tooltip: 'Open Bill',
        jumlah: snap.data?.length ?? 0,
        onTap: () => bukaDaftarOpenBill(context, widget.keranjang, repo: _repo),
      ),
    );
  }
}
