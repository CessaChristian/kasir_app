import 'package:flutter/material.dart';

import '../../../shared/ui/chip_status.dart';
import '../../../shared/ui/inisial_akun.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/currency_formatter.dart';
import '../models/ringkasan_shift.dart';

/// Kartu satu shift di Riwayat Shift (desain): inisial · nama · jam · status,
/// lalu Transaksi · Pendapatan · Pengeluaran, dan baris kecil "Kas awal ·
/// Kas akhir". Shift aktif bertepi hijau dan tanpa kas akhir (keputusan
/// owner: tulisan "Shift masih berjalan" di desain dibuang, chip Aktif sudah
/// cukup).
class KartuShift extends StatelessWidget {
  final RingkasanShift ringkasan;
  final DateTime sekarang;
  final VoidCallback onTap;

  const KartuShift({
    super.key,
    required this.ringkasan,
    required this.sekarang,
    required this.onTap,
  });

  static const _tepiAktif = Color(0xFFB9E0BF);

  @override
  Widget build(BuildContext context) {
    final r = ringkasan;
    final nama = r.namaKasir ?? 'Tanpa nama';
    final jam = r.aktif
        ? jamShift(r.shift)
        : '${jamShift(r.shift)} · ${durasiShift(r.shift, sekarang)}';
    final bentuk = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: r.aktif ? _tepiAktif : WarnaTeras.kartu),
    );
    return Material(
      color: WarnaTeras.kartu,
      shape: bentuk,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: bentuk,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  InisialKasir(nama: nama, ukuran: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nama,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TeksTeras.menu,
                            fontWeight: FontWeight.w600,
                            color: WarnaTeras.teks,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          jam,
                          style: const TextStyle(
                            fontSize: TeksTeras.kecil,
                            color: WarnaTeras.teksPudar,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChipStatus(
                    label: r.aktif ? 'Aktif' : 'Selesai',
                    aktif: r.aktif,
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: WarnaTeras.titikPasif,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: WarnaTeras.garis)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _angka(
                      'Transaksi',
                      '${r.jumlahTransaksi}',
                      WarnaTeras.teks,
                      flex: 10,
                    ),
                    _angka(
                      'Pendapatan',
                      formatRp(r.pendapatan),
                      WarnaTeras.oranye,
                    ),
                    _angka(
                      'Pengeluaran',
                      formatRp(r.totalPengeluaran),
                      WarnaTeras.merah,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _barisKas(r),
            ],
          ),
        ),
      ),
    );
  }

  /// "Kas awal Rp X" kiri, "Kas akhir Rp Y" kanan (shift selesai saja).
  /// Shift lama tanpa kas awal: "–".
  Widget _barisKas(RingkasanShift r) {
    const gaya = TextStyle(
      fontSize: TeksTeras.keterangan,
      color: WarnaTeras.teksPudar,
    );
    final awal = r.shift.kasAwal;
    final akhir = r.kasAkhir;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Kas awal ${awal == null ? '–' : formatRp(awal)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: gaya,
          ),
        ),
        if (!r.aktif)
          Flexible(
            child: Text(
              'Kas akhir ${akhir == null ? '–' : formatRp(akhir)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: (akhir ?? 0) < 0
                  ? gaya.copyWith(color: WarnaTeras.merah)
                  : gaya,
            ),
          ),
      ],
    );
  }

  /// Kolom desain 1 : 1.3 : 1.3.
  Widget _angka(String label, String nilai, Color warna, {int flex = 13}) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: TeksTeras.keterangan,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              nilai,
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w700,
                color: warna,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
