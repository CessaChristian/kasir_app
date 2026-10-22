import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'tombol_lembar.dart';
import 'warna_teras.dart';

/// Kerangka halaman Login dan Reset PIN (desain): latar oranye dengan logo
/// besar, lalu panel krem bertepi atas melengkung berisi judul dua baris
/// ("[judul]" + "Teras Inn") dan [isi].
///
/// [bungkus] membungkus area gulir — dipakai Login untuk tarik-segarkan.
/// [onKembali] memunculkan tombol kembali bulat putih di kiri atas.
///
/// Area logo memakai sisa tinggi layar sesudah panel ([_tinggiLogoMin]–
/// [_tinggiLogo]) — jadi Login (2 kolom) maupun Reset PIN (3 kolom) muat
/// tanpa digulir. Di layar pendek jarak antarkolom ([LabelMasuk],
/// [JarakMasuk]) juga dirapatkan. Saat keyboard muncul logo ikut menciut;
/// kalau tetap tidak muat, halaman bisa digulir.
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

  static const _tinggiLogoMin = 120.0;

  /// Di bawah tinggi ini jarak antarkolom dirapatkan.
  static const batasRapat = 760.0;

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
              // Tinggi di atas keyboard (Scaffold sudah mengecilkan badan
              // halaman): saat keyboard muncul area logo ikut menciut, jadi
              // kolom dan tombol tetap terlihat di atasnya.
              final tinggi = ukuran.maxHeight;
              final rapat = tinggi < batasRapat;
              final gulir = SingleChildScrollView(
                // WAJIB untuk tarik-segarkan: tanpa ini gerakan menarik
                // tidak terbaca saat isinya sudah muat di layar.
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: ukuran.maxHeight),
                  child: _TataMasuk(
                    tinggi: tinggi,
                    logoMin: _tinggiLogoMin,
                    logoMaks: _tinggiLogo,
                    logo: Stack(
                      children: [
                        Center(
                          child: FractionallySizedBox(
                            heightFactor: 0.8,
                            child: Image.asset(
                              'assets/images/logo_login.png',
                              fit: BoxFit.contain,
                              semanticLabel: 'Teras Inn',
                            ),
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
                    panel: Container(
                      // Keyboard sudah ditangani Scaffold (badan halaman
                      // mengecil), jadi cukup jarak bawah biasa.
                      padding: EdgeInsets.fromLTRB(
                        20,
                        rapat ? 24 : 32,
                        20,
                        rapat ? 20 : 28,
                      ),
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
                          _Rapat(
                            rapat: rapat,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: isi,
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Area logo + panel: panel diukur dulu, area logo mendapat sisa [tinggi]
/// (dibatasi [logoMin]–[logoMaks]), lalu panel direntang sampai bawah. Column tidak bisa begini — Flexible tidak
/// bisa diberi batas atas sambil menyerahkan sisanya ke panel.
class _TataMasuk extends MultiChildRenderObjectWidget {
  final double tinggi;
  final double logoMin;
  final double logoMaks;

  _TataMasuk({
    required this.tinggi,
    required this.logoMin,
    required this.logoMaks,
    required Widget logo,
    required Widget panel,
  }) : super(children: [logo, panel]);

  @override
  _RenderTataMasuk createRenderObject(BuildContext context) =>
      _RenderTataMasuk()
        ..tinggi = tinggi
        ..logoMin = logoMin
        ..logoMaks = logoMaks;

  @override
  void updateRenderObject(BuildContext context, _RenderTataMasuk r) {
    r
      ..tinggi = tinggi
      ..logoMin = logoMin
      ..logoMaks = logoMaks
      ..markNeedsLayout();
  }
}

class _DataTata extends ContainerBoxParentData<RenderBox> {}

class _RenderTataMasuk extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DataTata>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DataTata> {
  double tinggi = 0;
  double logoMin = 0;
  double logoMaks = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DataTata) child.parentData = _DataTata();
  }

  @override
  void performLayout() {
    final lebar = constraints.maxWidth;
    final logo = firstChild!;
    final panel = childAfter(logo)!;
    panel.layout(BoxConstraints.tightFor(width: lebar), parentUsesSize: true);
    final tinggiLogo = (tinggi - panel.size.height).clamp(logoMin, logoMaks);
    panel.layout(
      BoxConstraints(
        minWidth: lebar,
        maxWidth: lebar,
        minHeight: (tinggi - tinggiLogo).clamp(0, double.infinity),
      ),
      parentUsesSize: true,
    );
    logo.layout(BoxConstraints.tightFor(width: lebar, height: tinggiLogo));
    (logo.parentData! as _DataTata).offset = Offset.zero;
    (panel.parentData! as _DataTata).offset = Offset(0, tinggiLogo);
    size = constraints.constrain(Size(lebar, tinggiLogo + panel.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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

/// Penanda layar pendek untuk jarak di dalam [KerangkaMasuk].
class _Rapat extends InheritedWidget {
  final bool rapat;

  const _Rapat({required this.rapat, required super.child});

  /// Pengali jarak: 1 biasa, lebih kecil di layar pendek.
  static double pengali(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Rapat>()?.rapat == true
      ? 0.6
      : 1;

  @override
  bool updateShouldNotify(_Rapat lama) => lama.rapat != rapat;
}

/// Jarak tegak di halaman masuk; dirapatkan di layar pendek.
class JarakMasuk extends StatelessWidget {
  final double tinggi;

  const JarakMasuk(this.tinggi, {super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: tinggi * _Rapat.pengali(context));
}

/// Label di atas kolom halaman masuk.
class LabelMasuk extends StatelessWidget {
  final String teks;
  final double atas;

  const LabelMasuk(this.teks, {super.key, this.atas = 20});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: atas * _Rapat.pengali(context), bottom: 10),
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
