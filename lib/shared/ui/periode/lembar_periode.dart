import 'package:flutter/material.dart';

import '../teks_teras.dart';
import '../warna_teras.dart';
import 'metode_filter.dart';
import 'periode.dart';

/// Hasil lembar periode: periode dan metode bayar (Semua kalau lembarnya
/// dibuka tanpa bagian metode).
typedef HasilFilter = ({Periode periode, MetodeFilter metode});

/// Lembar "Pilih Periode": pilihan cepat, kalender tanggal, atau bulan.
///
/// Mengembalikan periode yang diterapkan, atau null kalau dibatalkan.
Future<Periode?> pilihPeriode(
  BuildContext context, {
  required Periode awal,
  DateTime? hariIni,
}) async =>
    (await _buka(context, awal: awal, metode: null, hariIni: hariIni))?.periode;

/// Versi Riwayat (desain "Filter Riwayat"): lembar yang sama ditambah
/// bagian Metode pembayaran.
Future<HasilFilter?> pilihFilterRiwayat(
  BuildContext context, {
  required Periode awal,
  required MetodeFilter metode,
  DateTime? hariIni,
}) => _buka(context, awal: awal, metode: metode, hariIni: hariIni);

Future<HasilFilter?> _buka(
  BuildContext context, {
  required Periode awal,
  required MetodeFilter? metode,
  DateTime? hariIni,
}) {
  return showModalBottomSheet<HasilFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LembarPeriode(
      awal: awal,
      metodeAwal: metode,
      hariIni: hariIni ?? DateTime.now(),
    ),
  );
}

class LembarPeriode extends StatefulWidget {
  final Periode awal;
  final DateTime hariIni;

  /// Null = tanpa bagian metode bayar (mis. Pengeluaran).
  final MetodeFilter? metodeAwal;

  const LembarPeriode({
    super.key,
    required this.awal,
    required this.hariIni,
    this.metodeAwal,
  });

  @override
  State<LembarPeriode> createState() => _LembarPeriodeState();
}

class _LembarPeriodeState extends State<LembarPeriode> {
  late final DateTime _hariIni = DateTime(
    widget.hariIni.year,
    widget.hariIni.month,
    widget.hariIni.day,
  );

  var _modeBulan = false;
  late MetodeFilter? _metode = widget.metodeAwal;

  // Mode tanggal. [_sampai] null = sedang menunggu tanggal akhir.
  late DateTime _dari = widget.awal.dari;
  late DateTime? _sampai = widget.awal.sampai;
  late DateTime _tampilBulan = DateTime(
    widget.awal.sampai.year,
    widget.awal.sampai.month,
  );

  // Mode bulan (hari selalu 1).
  late DateTime _bulanDari = DateTime(
    widget.awal.dari.year,
    widget.awal.dari.month,
  );
  late DateTime? _bulanSampai = DateTime(
    widget.awal.sampai.year,
    widget.awal.sampai.month,
  );
  late int _tampilTahun = widget.awal.sampai.year;

  bool get _menungguAkhir =>
      _modeBulan ? _bulanSampai == null : _sampai == null;

  Periode get _draf => _modeBulan
      ? periodeBulan(_bulanDari, _bulanSampai ?? _bulanDari, _hariIni)
      : Periode(_dari, _sampai ?? _dari);

  void _setel(Periode p) => setState(() {
    _modeBulan = false;
    _dari = p.dari;
    _sampai = p.sampai;
    _tampilBulan = DateTime(p.sampai.year, p.sampai.month);
  });

  void _reset() => setState(() {
    _setel(Periode.hari(_hariIni));
    if (_metode != null) _metode = MetodeFilter.semua;
    _bulanDari = DateTime(_hariIni.year, _hariIni.month);
    _bulanSampai = _bulanDari;
    _tampilTahun = _hariIni.year;
  });

  void _ketukTanggal(DateTime d) => setState(() {
    if (_sampai == null && !d.isBefore(_dari)) {
      _sampai = d;
    } else {
      _dari = d;
      _sampai = null;
    }
  });

  void _ketukBulan(DateTime b) => setState(() {
    if (_bulanSampai == null && !b.isBefore(_bulanDari)) {
      _bulanSampai = b;
    } else {
      _bulanDari = b;
      _bulanSampai = null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final draf = _draf;
    final teksDraf = _modeBulan ? _labelRentangBulan() : labelPeriode(draf);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: WarnaTeras.garis,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: WarnaTeras.oranyeMuda,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: WarnaTeras.oranye,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _metode == null ? 'Pilih Periode' : 'Filter Riwayat',
                      style: TextStyle(
                        fontSize: TeksTeras.menu,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                    Text(
                      teksDraf + (_menungguAkhir ? ' · pilih akhir' : ''),
                      style: const TextStyle(
                        fontSize: TeksTeras.kecil,
                        color: WarnaTeras.teksPudar,
                      ),
                    ),
                  ],
                ),
              ),
              ChipReset(onTap: _reset),
            ],
          ),
          const SizedBox(height: 14),
          // Satu baris yang digeser ke samping (desain), bukan dilipat.
          // Melebar sampai tepi lembar supaya chip terakhir tidak terpotong
          // padding.
          SizedBox(
            height: 32,
            child: OverflowBox(
              maxWidth: MediaQuery.sizeOf(context).width,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final (nama, p) in pintasanPeriode(_hariIni))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _chip(
                        nama,
                        aktif: !_modeBulan && draf == p && !_menungguAkhir,
                        onTap: () => _setel(p),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _tab(),
          const SizedBox(height: 10),
          _navigasi(),
          const SizedBox(height: 6),
          if (_modeBulan) _gridBulan() else _kalender(),
          if (_metode != null) ..._bagianMetode(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WarnaTeras.teks,
                    side: const BorderSide(color: WarnaTeras.garis),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Batal',
                    style: TextStyle(fontSize: TeksTeras.biasa),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop<HasilFilter>(context, (
                    periode: draf,
                    metode: _metode ?? MetodeFilter.semua,
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: WarnaTeras.oranye,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Terapkan',
                    style: TextStyle(
                      fontSize: TeksTeras.biasa,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bagian "Metode pembayaran" (khusus filter Riwayat).
  List<Widget> _bagianMetode() => [
    const SizedBox(height: 12),
    Container(height: 1, color: WarnaTeras.garis),
    const SizedBox(height: 12),
    const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Metode pembayaran',
        style: TextStyle(
          fontSize: TeksTeras.biasa,
          fontWeight: FontWeight.w600,
          color: WarnaTeras.teks,
        ),
      ),
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        for (final m in MetodeFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _chipMetode(m),
          ),
      ],
    ),
  ];

  Widget _chipMetode(MetodeFilter m) {
    final aktif = _metode == m;
    return Material(
      color: aktif ? WarnaTeras.oranyeMuda : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
        side: BorderSide(
          color: aktif ? WarnaTeras.oranye : const Color(0xFFE6DED6),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _metode = m),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                m.ikon,
                size: 17,
                color: aktif ? WarnaTeras.oranye : const Color(0xFF5A5048),
              ),
              const SizedBox(width: 5),
              Text(
                m.label,
                style: TextStyle(
                  fontSize: TeksTeras.kecil,
                  fontWeight: FontWeight.w600,
                  color: aktif ? WarnaTeras.oranye : const Color(0xFF5A5048),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelRentangBulan() {
    String b(DateTime d) => '${namaBulanPendek[d.month - 1]} ${d.year}';
    final akhir = _bulanSampai ?? _bulanDari;
    return akhir == _bulanDari
        ? b(_bulanDari)
        : '${b(_bulanDari)} – ${b(akhir)}';
  }

  Widget _chip(
    String label, {
    required bool aktif,
    required VoidCallback onTap,
  }) {
    return Material(
      color: aktif ? WarnaTeras.oranye : WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
        side: BorderSide(
          color: aktif ? WarnaTeras.oranye : const Color(0xFFE6DED6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w600,
              color: aktif ? Colors.white : WarnaTeras.teksSedang,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab() {
    Widget tombol(String label, bool bulan) {
      final aktif = _modeBulan == bulan;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _modeBulan = bulan),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: aktif ? WarnaTeras.kartu : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: aktif
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: TeksTeras.biasa,
                fontWeight: FontWeight.w600,
                color: aktif ? WarnaTeras.teks : WarnaTeras.teksPudar,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EEE8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [tombol('Tanggal', false), tombol('Bulan', true)]),
    );
  }

  Widget _navigasi() {
    final bisaMaju = _modeBulan
        ? _tampilTahun < _hariIni.year
        : DateTime(
            _tampilBulan.year,
            _tampilBulan.month + 1,
          ).isBefore(DateTime(_hariIni.year, _hariIni.month + 1));
    final judul = _modeBulan
        ? '$_tampilTahun'
        : '${namaBulanPanjang[_tampilBulan.month - 1]} ${_tampilBulan.year}';
    return Row(
      children: [
        IconButton(
          tooltip: 'Sebelumnya',
          onPressed: () => setState(() {
            if (_modeBulan) {
              _tampilTahun--;
            } else {
              _tampilBulan = DateTime(
                _tampilBulan.year,
                _tampilBulan.month - 1,
              );
            }
          }),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            judul,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teks,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Berikutnya',
          onPressed: bisaMaju
              ? () => setState(() {
                  if (_modeBulan) {
                    _tampilTahun++;
                  } else {
                    _tampilBulan = DateTime(
                      _tampilBulan.year,
                      _tampilBulan.month + 1,
                    );
                  }
                })
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _kalender() {
    const hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final awalBulan = _tampilBulan;
    final jumlahHari = DateTime(awalBulan.year, awalBulan.month + 1, 0).day;
    final kosong = awalBulan.weekday - 1; // Senin = 0
    final akhir = _sampai ?? _dari;

    return Column(
      children: [
        Row(
          children: [
            for (final h in hari)
              Expanded(
                child: Text(
                  h,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TeksTeras.keterangan,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          children: [
            for (var i = 0; i < kosong; i++) const SizedBox(),
            for (var d = 1; d <= jumlahHari; d++)
              _sel(
                label: '$d',
                tanggal: DateTime(awalBulan.year, awalBulan.month, d),
                dari: _dari,
                sampai: akhir,
                hariIni: _hariIni,
                onTap: _ketukTanggal,
              ),
          ],
        ),
      ],
    );
  }

  Widget _gridBulan() {
    final akhir = _bulanSampai ?? _bulanDari;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (var m = 1; m <= 12; m++)
          _sel(
            label: namaBulanPendek[m - 1],
            tanggal: DateTime(_tampilTahun, m),
            dari: _bulanDari,
            sampai: akhir,
            hariIni: DateTime(_hariIni.year, _hariIni.month),
            onTap: _ketukBulan,
            kotak: true,
          ),
      ],
    );
  }

  /// Satu sel kalender/bulan: ujung rentang oranye, isinya oranye muda,
  /// hari ini bertepi oranye, masa depan tidak bisa dipilih.
  Widget _sel({
    required String label,
    required DateTime tanggal,
    required DateTime dari,
    required DateTime sampai,
    required DateTime hariIni,
    required ValueChanged<DateTime> onTap,
    bool kotak = false,
  }) {
    final masaDepan = tanggal.isAfter(hariIni);
    final ujung = tanggal == dari || tanggal == sampai;
    final diDalam = !tanggal.isBefore(dari) && !tanggal.isAfter(sampai);
    final latar = ujung
        ? WarnaTeras.oranye
        : diDalam
        ? WarnaTeras.oranyeMuda
        : (kotak ? const Color(0xFFF7F4F1) : Colors.transparent);
    final warna = masaDepan
        ? const Color(0xFFD6D0CA)
        : ujung
        ? Colors.white
        : diDalam
        ? const Color(0xFFC96E17)
        : WarnaTeras.teks;

    return GestureDetector(
      onTap: masaDepan ? null : () => onTap(tanggal),
      child: Container(
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tanggal == hariIni && !ujung
                ? WarnaTeras.oranye
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: TeksTeras.biasa,
            fontWeight: ujung ? FontWeight.w700 : FontWeight.w500,
            color: warna,
          ),
        ),
      ),
    );
  }
}

/// Chip abu-abu kecil "⟲ Reset".
class ChipReset extends StatelessWidget {
  final VoidCallback onTap;

  const ChipReset({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4EEE8),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restart_alt_rounded,
                size: 15,
                color: Color(0xFF5A5048),
              ),
              SizedBox(width: 3),
              Text(
                'Reset',
                style: TextStyle(
                  fontSize: TeksTeras.kecil,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A5048),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
