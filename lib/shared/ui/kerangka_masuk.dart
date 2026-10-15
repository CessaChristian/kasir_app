import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tombol_lembar.dart';
import 'warna_teras.dart';

/// Kerangka halaman Login dan Reset PIN (desain): latar oranye dengan logo
/// besar, lalu panel krem bertepi atas melengkung berisi judul dua baris
/// ("[judul]" + "Teras Inn") dan [isi].
///
/// [bungkus] membungkus area gulir — dipakai Login untuk tarik-segarkan.
/// [onKembali] memunculkan tombol kembali bulat putih di kiri atas.
class KerangkaMasuk extends StatelessWidget {
  final String judul;
  final List<Widget> isi;
  final VoidCallback? onKembali;
  final Widget Function(Widget gulir)? bungkus;

  const KerangkaMasuk({
    super.key,
    required this.judul,
    required this.isi,
    this.onKembali,
    this.bungkus,
  });

  static const _tinggiLogo = 320.0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: WarnaTeras.oranyeCerah,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, ukuran) {
              final gulir = SingleChildScrollView(
                // WAJIB untuk tarik-segarkan: tanpa ini gerakan menarik
                // tidak terbaca saat isinya sudah muat di layar.
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: ukuran.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _tinggiLogo,
                        child: Stack(
                          children: [
                            Center(
                              child: Image.asset(
                                'assets/images/logo_login.png',
                                width: 260,
                                height: 260,
                                fit: BoxFit.contain,
                                semanticLabel: 'Teras Inn',
                              ),
                            ),
                            if (onKembali != null)
                              Positioned(
                                top: 10,
                                left: 18,
                                child: _TombolKembali(onTap: onKembali!),
                              ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: ukuran.maxHeight - _tinggiLogo,
                        ),
                        child: Container(
                          // Keyboard sudah ditangani Scaffold (badan halaman
                          // mengecil), jadi cukup jarak bawah biasa.
                          padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
                          decoration: BoxDecoration(
                            color: WarnaTeras.latar,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.elliptical(ukuran.maxWidth / 2, 72),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                judul,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: WarnaTeras.teks,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Teras Inn',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: WarnaTeras.oranyeCerah,
                                ),
                              ),
                              ...isi,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return bungkus?.call(gulir) ?? gulir;
            },
          ),
        ),
      ),
    );
  }
}

class _TombolKembali extends StatelessWidget {
  final VoidCallback onTap;

  const _TombolKembali({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: WarnaTeras.teks,
            semanticLabel: 'Kembali',
          ),
        ),
      ),
    );
  }
}

/// Label di atas kolom halaman masuk.
class LabelMasuk extends StatelessWidget {
  final String teks;
  final double atas;

  const LabelMasuk(this.teks, {super.key, this.atas = 20});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: atas, bottom: 10),
      child: Text(
        teks,
        style: const TextStyle(fontSize: 16, color: WarnaTeras.teks),
      ),
    );
  }
}

/// Kolom isian halaman masuk (desain): kotak putih bersudut dengan ikon
/// abu di kiri. [rahasia] = PIN: disembunyikan dengan tombol mata di kanan.
/// [galat] memerahkan tepinya. [latar] bawaan putih; Daftarkan Perangkat
/// memakai krem halaman. [namaRahasia] untuk label tombol mata.
/// [jarakHuruf] bawaan: 4 untuk kolom rahasia (titik PIN renggang), 0 untuk
/// yang lain.
class KolomMasuk extends StatefulWidget {
  final TextEditingController controller;
  final IconData ikon;
  final String petunjuk;
  final bool rahasia;
  final bool galat;
  final bool aktif;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Color latar;
  final String namaRahasia;
  final double? jarakHuruf;

  const KolomMasuk({
    super.key,
    required this.controller,
    required this.ikon,
    required this.petunjuk,
    this.rahasia = false,
    this.galat = false,
    this.aktif = true,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.latar = Colors.white,
    this.namaRahasia = 'PIN',
    this.jarakHuruf,
  });

  @override
  State<KolomMasuk> createState() => _KolomMasukState();
}

class _KolomMasukState extends State<KolomMasuk> {
  var _sembunyi = true;

  @override
  Widget build(BuildContext context) {
    final sembunyi = widget.rahasia && _sembunyi;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: widget.aktif ? widget.latar : WarnaTeras.latarAbu,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.galat ? WarnaTeras.merah : const Color(0xFFCFC8C1),
        ),
      ),
      child: Row(
        children: [
          Icon(widget.ikon, size: 24, color: WarnaTeras.teksSamar),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.aktif,
              autofocus: widget.autofocus,
              obscureText: sembunyi,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                fontSize: 18,
                letterSpacing: widget.jarakHuruf ?? (widget.rahasia ? 4 : 0),
                color: WarnaTeras.teks,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.petunjuk,
                hintStyle: const TextStyle(color: Color(0xFFB5ADA6)),
              ),
            ),
          ),
          if (widget.rahasia)
            GestureDetector(
              onTap: () => setState(() => _sembunyi = !_sembunyi),
              child: Icon(
                _sembunyi
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 24,
                color: const Color(0xFF6B6058),
                semanticLabel: _sembunyi
                    ? 'Tampilkan ${widget.namaRahasia}'
                    : 'Sembunyikan ${widget.namaRahasia}',
              ),
            ),
        ],
      ),
    );
  }
}

/// Baris pesan galat merah halaman masuk; [kanan] mis. "Lupa PIN Owner?".
class BarisGalatMasuk extends StatelessWidget {
  final String? galat;
  final Widget? kanan;

  const BarisGalatMasuk({super.key, required this.galat, this.kanan});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              galat ?? '',
              style: const TextStyle(fontSize: 14, color: WarnaTeras.merah),
            ),
          ),
          ?kanan,
        ],
      ),
    );
  }
}

/// Tombol utama halaman masuk: oranye cerah.
class TombolMasuk extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const TombolMasuk({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TombolLembar(
      label: label,
      latar: WarnaTeras.oranyeCerah,
      warna: Colors.white,
      tinggi: 56,
      sudut: 8,
      ukuranTeks: 18,
      beratTeks: FontWeight.w600,
      onPressed: onPressed,
    );
  }
}
