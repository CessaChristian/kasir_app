import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../shared/ui/warna_teras.dart';
import '../pages/daftar_perangkat_page.dart';

/// "1 HP perlu dicek" di Dashboard owner (QA kedua S10).
///
/// Masalah HP lain — data yang gagal terkirim, data tertahan, HP yang diam
/// seminggu — dulu hanya terlihat kalau owner membuka Daftar Perangkat.
/// Strip ini memakai hitungan yang sama ([Perangkat.perluPerhatian]) dan
/// mengantar ke sana untuk penjelasannya. Tidak tampil kalau semuanya sehat
/// atau daftar tidak terbaca (offline).
class PeringatanPerangkat extends StatefulWidget {
  /// Pengganti pemuat daftar, untuk test.
  final Future<List<Perangkat>> Function()? muat;
  final String? idSaya;

  const PeringatanPerangkat({super.key, this.muat, this.idSaya});

  @override
  State<PeringatanPerangkat> createState() => _PeringatanPerangkatState();
}

class _PeringatanPerangkatState extends State<PeringatanPerangkat> {
  List<Perangkat> _bermasalah = const [];

  @override
  void initState() {
    super.initState();
    _muat();
    // Kabar HP lain datang lewat sinkron.
    SyncService.instance.terakhirBerhasil.addListener(_muat);
  }

  @override
  void dispose() {
    SyncService.instance.terakhirBerhasil.removeListener(_muat);
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final daftar =
          await (widget.muat ?? PerangkatRepository.instance.semua)();
      final idSaya = widget.idSaya ?? PerangkatRepository.instance.idSaya;
      if (!mounted) return;
      setState(() {
        _bermasalah = [
          for (final p in daftar)
            if (p.perluPerhatian(idSaya: idSaya)) p,
        ];
      });
    } catch (_) {
      // Offline: tidak ada yang bisa dikatakan.
    }
  }

  Future<void> _buka() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DaftarPerangkatPage()),
    );
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (_bermasalah.isEmpty) return const SizedBox.shrink();
    final n = _bermasalah.length;
    final gagalKirim = _bermasalah.any((p) => p.jumlahGagalKirim > 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _buka,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF6C894)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.phonelink_erase_rounded,
                  size: 20,
                  color: WarnaTeras.oranye,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$n HP perlu dicek'
                    '${gagalKirim ? ' — ada data yang gagal terkirim' : ''}. '
                    'Ketuk untuk buka Daftar Perangkat.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WarnaTeras.oranye,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
