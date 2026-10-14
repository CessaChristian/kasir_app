import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/ui/warna_teras.dart';
import '../models/format_shift.dart';

/// Satu shift lama yang bisa dibuka/tutup (Riwayat Pengeluaran dan Riwayat
/// Transaksi kasir): "Rabu, 30 Sep · 08:02–16:10", [keterangan], [total]
/// berwarna [warnaTotal]; terbuka = [isi] di bawahnya.
class KartuShiftLipat extends StatefulWidget {
  final DateTime mulai;
  final DateTime? selesai;
  final String keterangan;
  final String total;
  final Color warnaTotal;
  final List<Widget> Function() isi;

  /// Tanpa garis atas (baris pertama di kartunya).
  final bool pertama;
  final ValueChanged<bool>? onBerubah;

  const KartuShiftLipat({
    super.key,
    required this.mulai,
    required this.selesai,
    required this.keterangan,
    required this.total,
    required this.warnaTotal,
    required this.isi,
    this.pertama = false,
    this.onBerubah,
  });

  @override
  State<KartuShiftLipat> createState() => _KartuShiftLipatState();
}

class _KartuShiftLipatState extends State<KartuShiftLipat> {
  var _terbuka = false;

  @override
  Widget build(BuildContext context) {
    final judul =
        '${DateFormat('EEEE, d MMM', 'id_ID').format(widget.mulai)} · '
        '${rentangShift(widget.mulai, widget.selesai, widget.mulai)}';
    return Container(
      decoration: widget.pertama
          ? null
          : const BoxDecoration(
              border: Border(top: BorderSide(color: WarnaTeras.garis)),
            ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() => _terbuka = !_terbuka);
              widget.onBerubah?.call(_terbuka);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
              child: Row(
                children: [
                  Icon(
                    _terbuka
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 22,
                    color: WarnaTeras.teksPudar,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          judul,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: WarnaTeras.teks,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.keterangan,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WarnaTeras.teksPudar,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.total,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: widget.warnaTotal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_terbuka) ...[
            const Divider(height: 1, thickness: 1, color: WarnaTeras.garis),
            ...widget.isi(),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
