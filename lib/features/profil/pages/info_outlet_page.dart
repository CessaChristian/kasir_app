import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_database.dart';
import '../../../data/db.dart';
import '../../../shared/constants/info_nota.dart';
import '../../../shared/ui/halaman_turunan.dart';
import '../../../shared/ui/kolom_isian.dart';
import '../../../shared/ui/lembar_konfirmasi.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/simpan_lalu_kirim.dart';
import '../../printer/data/struk_cetak.dart';

/// Profil owner → Info Outlet: alamat, nomor HP, dan WiFi yang tercetak di
/// nota (permintaan owner 11 Nov 2026). Nama toko tidak bisa diubah.
///
/// Tombol "Simpan Perubahan" baru naik dari bawah begitu isinya BERBEDA
/// dari yang tersimpan, dan turun lagi kalau isinya dikembalikan seperti
/// semula. Sebelum disimpan owner melihat ringkasan sebelum → sesudah.
///
/// Tidak wajib online: tersimpan di HP dan terkirim begitu tersambung.
class InfoOutletPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final AppDatabase? basis;

  const InfoOutletPage({super.key, this.basis});

  @override
  State<InfoOutletPage> createState() => _InfoOutletPageState();
}

class _InfoOutletPageState extends State<InfoOutletPage> {
  late final _db = widget.basis ?? db;

  /// Yang tersimpan — pembanding isian.
  late InfoNota _awal = InfoNota.kini.value;

  late final _alamat = TextEditingController(text: _awal.alamat);
  late final _noHp = TextEditingController(text: _awal.noHp);
  late final _wifiNama = TextEditingController(text: _awal.wifiNama);
  late final _wifiSandi = TextEditingController(text: _awal.wifiSandi);

  bool _menyimpan = false;

  InfoNota get _isian => InfoNota.rapikan(
    alamat: _alamat.text,
    noHp: _noHp.text,
    wifiNama: _wifiNama.text,
    wifiSandi: _wifiSandi.text,
  );

  @override
  void dispose() {
    _alamat.dispose();
    _noHp.dispose();
    _wifiNama.dispose();
    _wifiSandi.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final baru = _isian;
    if (!baru.sah || _menyimpan) return;
    FocusScope.of(context).unfocus();

    String isi(String s) => s.isEmpty ? '(kosong)' : s;
    final beda = [
      if (baru.alamat != _awal.alamat)
        'Alamat: ${isi(_awal.alamat)} → ${isi(baru.alamat)}',
      if (baru.noHp != _awal.noHp)
        'No. HP: ${isi(_awal.noHp)} → ${isi(baru.noHp)}',
      if (baru.wifiNama != _awal.wifiNama)
        'WiFi: ${isi(_awal.wifiNama)} → ${isi(baru.wifiNama)}',
      if (baru.wifiSandi != _awal.wifiSandi)
        'Sandi WiFi: ${isi(_awal.wifiSandi)} → ${isi(baru.wifiSandi)}',
    ];
    final ya = await tampilkanLembarKonfirmasi(
      context,
      ikon: Icons.receipt_long_rounded,
      judul: 'Simpan info outlet?',
      catatan:
          '${beda.join('\n')}\n\n'
          'Berlaku untuk semua nota yang dicetak sesudah ini, termasuk '
          'cetak ulang nota lama.',
      labelAksi: 'Simpan',
      warnaAksi: WarnaTeras.oranye,
      latarIkon: WarnaTeras.oranyeMuda,
      warnaIkon: WarnaTeras.oranye,
    );
    if (!ya || !mounted) return;

    setState(() => _menyimpan = true);
    final tersimpan = await simpanLaluKirim(
      context,
      simpan: () => _db.simpanInfoToko(
        alamat: baru.alamat,
        noHp: baru.noHp,
        wifiNama: baru.wifiNama,
        wifiSandi: baru.wifiSandi,
      ),
      pesanTerkirim: 'Info outlet disimpan · langsung berlaku di semua HP',
      pesanTertunda: 'Info outlet disimpan · berlaku di HP lain setelah online',
    );
    if (!mounted) return;
    setState(() {
      _menyimpan = false;
      if (tersimpan) _awal = baru;
    });
  }

  Future<void> _kembali() async {
    final buang = await tanyaBuangPerubahan(
      context,
      catatan: 'Perubahan info outlet yang belum disimpan akan hilang.',
    );
    if (buang && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isian = _isian;
    final berubah = isian != _awal;
    return PopScope(
      canPop: !berubah,
      onPopInvokedWithResult: (sudah, _) {
        if (!sudah) _kembali();
      },
      child: HalamanTurunan(
        judul: 'Info Outlet',
        child: Column(
          children: [
            Expanded(
              child: IgnorePointer(
                ignoring: _menyimpan,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _kartu(
                      judul: 'Tercetak di kepala nota',
                      children: [
                        _kolom(
                          kunci: 'alamat',
                          controller: _alamat,
                          label: 'Alamat',
                          ikon: Icons.place_rounded,
                          panjang: InfoNota.panjangAlamat,
                          kapital: TextCapitalization.words,
                          galat: isian.galatAlamat,
                        ),
                        _kolom(
                          kunci: 'no_hp',
                          controller: _noHp,
                          label: 'Nomor HP',
                          ikon: Icons.phone_rounded,
                          panjang: InfoNota.panjangNoHp,
                          keyboard: TextInputType.phone,
                          galat: isian.galatNoHp,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _kartu(
                      judul: 'WiFi di bawah nota',
                      keterangan:
                          'Kosongkan nama WiFi kalau tidak ingin dicetak.',
                      children: [
                        _kolom(
                          kunci: 'wifi_nama',
                          controller: _wifiNama,
                          label: 'Nama WiFi',
                          ikon: Icons.wifi_rounded,
                          panjang: InfoNota.panjangWifi,
                          galat: isian.galatWifiNama,
                        ),
                        _kolom(
                          kunci: 'wifi_sandi',
                          controller: _wifiSandi,
                          label: 'Sandi WiFi',
                          ikon: Icons.key_rounded,
                          panjang: InfoNota.panjangWifi,
                          galat: isian.galatWifiSandi,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _pratinjau(isian),
                  ],
                ),
              ),
            ),
            // Naik dari bawah saat ada perubahan, turun lagi saat isinya
            // kembali seperti yang tersimpan.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (anak, animasi) => SizeTransition(
                sizeFactor: animasi,
                alignment: Alignment.topCenter,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(animasi),
                  child: anak,
                ),
              ),
              child: berubah || _menyimpan
                  ? Padding(
                      key: const ValueKey('simpan_info_outlet'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: TombolLembar(
                        label: _menyimpan ? 'Menyimpan…' : 'Simpan Perubahan',
                        ikon: Icons.save_rounded,
                        latar: WarnaTeras.oranye,
                        warna: Colors.white,
                        latarNonaktif: const Color(0xFFE2E0DE),
                        warnaNonaktif: const Color(0xFFA8A29C),
                        tinggi: 46,
                        sudut: 12,
                        onPressed: isian.sah && !_menyimpan ? _simpan : null,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartu({
    required String judul,
    String? keterangan,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            judul,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teks,
            ),
          ),
          if (keterangan != null) ...[
            const SizedBox(height: 2),
            Text(
              keterangan,
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                color: WarnaTeras.teksPudar,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kolom({
    required String kunci,
    required TextEditingController controller,
    required String label,
    required IconData ikon,
    required int panjang,
    required String? galat,
    TextInputType? keyboard,
    TextCapitalization kapital = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KolomIsian(
            key: ValueKey('kolom_$kunci'),
            controller: controller,
            label: label,
            ikon: ikon,
            keyboardType: keyboard,
            textCapitalization: kapital,
            inputFormatters: [LengthLimitingTextInputFormatter(panjang)],
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          if (galat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                galat,
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.merah,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Kepala dan kaki nota seperti yang akan tercetak, mengikuti isian.
  Widget _pratinjau(InfoNota isian) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pratinjau nota',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WarnaTeras.teks,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('pratinjau_nota'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE6DED6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (final b in susunPratinjauInfo(isian))
                  Text(
                    b.teks.isEmpty ? ' ' : b.teks,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: b.tebal ? FontWeight.w700 : FontWeight.w400,
                      color: WarnaTeras.teks,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
