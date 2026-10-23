import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../data/supabase/supabase_service.dart';
import '../../../shared/ui/kerangka_masuk.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../shared/widgets/app_toast.dart';

/// Pesan untuk jawaban pendaftaran selain "diterima".
String pesanHasilKunci(HasilKunci hasil) => switch (hasil) {
  HasilKunci.salah => 'Kunci pemasangan tidak valid',
  HasilKunci.terlaluBanyak =>
    'Terlalu banyak percobaan kunci yang salah. Coba lagi 1 jam lagi.',
  HasilKunci.dicabut =>
    'HP ini dicabut pemilik. Minta pemilik memulihkannya dari halaman '
        'Perangkat.',
  _ => 'Pendaftaran gagal. Periksa koneksi lalu coba lagi.',
};

/// Layar pertama di HP yang belum pernah didaftarkan.
///
/// ── KENAPA ADA ──
///
/// Dulu kredensial perangkat ditanam ke APK saat build, sehingga setiap HP
/// baru butuh APK-nya sendiri — artinya butuh programmer — dan rahasianya
/// bisa dikorek dari berkas APK. Sekarang pemilik mengetik kunci pemasangan
/// sekali di sini, lalu HP ini mendapat identitasnya sendiri.
///
/// ── KENAPA WAJIB ONLINE ──
///
/// Yang memutuskan kunci itu benar atau salah adalah server. Tanpa jaringan
/// tidak ada yang bisa memastikannya, dan menerima kunci apa pun secara lokal
/// sama saja tidak mengunci apa-apa.
class DaftarkanPerangkatPage extends StatefulWidget {
  /// Dipanggil setelah pendaftaran berhasil, untuk melanjutkan alur pembukaan.
  final Future<void> Function() sesudahBerhasil;

  /// HP ini SUDAH punya identitas, yang kurang cuma barisnya di daftar.
  ///
  /// Terjadi pada HP yang terpasang sebelum daftarnya dibuat di server, dan
  /// pada HP yang barisnya dilupakan pemilik. Bedanya nyata: identitasnya
  /// tidak dibuat ulang, jadi tidak ada identitas yatim yang ditinggalkan —
  /// dan emailnya tidak perlu ditanyakan lagi, karena pada tahap ini yang
  /// memeriksa kunci adalah server, bukan halaman login.
  final bool lengkapiSaja;

  /// Diisi test; aplikasi memakai layanan server sungguhan.
  final Future<HasilDaftarPerangkat> Function()? buatIdentitas;
  final Future<HasilKunci> Function(String kunci)? periksaKunci;
  final Future<void> Function()? lepaskanIdentitas;

  const DaftarkanPerangkatPage({
    super.key,
    required this.sesudahBerhasil,
    this.lengkapiSaja = false,
    this.buatIdentitas,
    this.periksaKunci,
    this.lepaskanIdentitas,
  });

  @override
  State<DaftarkanPerangkatPage> createState() => _DaftarkanPerangkatPageState();
}

class _DaftarkanPerangkatPageState extends State<DaftarkanPerangkatPage> {
  final _kunciC = TextEditingController();

  bool _sedangMendaftar = false;
  String? _galat;

  @override
  void dispose() {
    _kunciC.dispose();
    super.dispose();
  }

  Future<void> _daftar() async {
    if (_sedangMendaftar) return;
    if (_kunciC.text.isEmpty) {
      setState(() => _galat = 'Kunci pemasangan wajib diisi');
      return;
    }
    setState(() {
      _sedangMendaftar = true;
      _galat = null;
    });

    // Identitas dibuat hanya kalau HP ini memang belum punya. Yang sudah punya
    // cukup dicatatkan — membuat identitas baru berarti meninggalkan yang lama
    // sebagai baris yatim di daftar pengguna server.
    var identitasBaru = !widget.lengkapiSaja;
    if (identitasBaru && !await _buatIdentitas()) return;

    // Di sinilah kuncinya benar-benar diperiksa, oleh server.
    final periksa =
        widget.periksaKunci ?? PerangkatRepository.instance.daftarkanIdentitasIni;
    var hasil = await periksa(_kunciC.text);
    if (!mounted) return;

    // Identitas lama sudah dihapus server (HP ini dilupakan pemilik): HP ini
    // kembali seperti HP baru. Sekali saja, dengan identitas baru.
    if (hasil == HasilKunci.identitasHilang && !identitasBaru) {
      identitasBaru = true;
      if (!await _buatIdentitas()) return;
      hasil = await periksa(_kunciC.text);
      if (!mounted) return;
    }

    if (hasil != HasilKunci.diterima) {
      // Identitas yang tidak diakui siapa pun jangan ditinggalkan menggantung.
      if (identitasBaru) {
        await (widget.lepaskanIdentitas ??
            SupabaseService.instance.lepaskanPerangkat)();
      }
      if (!mounted) return;
      setState(() {
        _sedangMendaftar = false;
        _galat = pesanHasilKunci(hasil);
      });
      return;
    }

    // Toast baru muncul setelah halaman berikutnya (Login) tampil — HP baru
    // masih menarik data toko dulu, dan toast yang muncul lebih awal sudah
    // hilang sebelum Login terlihat. Lapisannya diambil sekarang karena
    // halaman ini sudah tertutup saat itu.
    final lapisan = Overlay.of(context);
    await widget.sesudahBerhasil();
    AppToast.successDi(lapisan, 'Perangkat berhasil didaftarkan');
  }

  /// Minta identitas baru. False (dengan pesan) kalau gagal.
  Future<bool> _buatIdentitas() async {
    final hasil = await (widget.buatIdentitas ??
        SupabaseService.instance.buatIdentitasBaru)();
    if (!mounted) return false;
    if (hasil == HasilDaftarPerangkat.berhasil) return true;
    setState(() {
      _sedangMendaftar = false;
      _galat = hasil == HasilDaftarPerangkat.jaringan
          ? 'Tidak bisa menghubungi server. Pendaftaran perangkat butuh '
                'internet — periksa koneksi lalu coba lagi.'
          : 'Pendaftaran gagal. Coba lagi sebentar lagi.';
    });
    return false;
  }

  void _hapusGalat(String _) {
    if (_galat != null) setState(() => _galat = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarnaTeras.latar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFBE6D3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.key_rounded,
                      size: 36,
                      color: WarnaTeras.oranyeCerah,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.lengkapiSaja
                      ? 'Lengkapi Pendaftaran'
                      : 'Daftarkan Perangkat',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A1F17),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 310),
                    child: Text(
                      widget.lengkapiSaja
                          ? 'Masukkan kunci pemasangan dari pemilik untuk '
                                'menghubungkan HP ini ke data toko. Data di HP '
                                'ini tidak berubah.'
                          : 'HP ini belum terdaftar. Masukkan kunci '
                                'pemasangan dari pemilik untuk '
                                'menghubungkannya ke data toko.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Color(0xFF7A706A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                KolomMasuk(
                  controller: _kunciC,
                  ikon: Icons.lock_outline_rounded,
                  petunjuk: 'Kunci pemasangan',
                  rahasia: true,
                  namaRahasia: 'kunci',
                  // Jarak renggang ala PIN membuat petunjuknya terlalu lebar.
                  jarakHuruf: 0,
                  latar: WarnaTeras.latar,
                  galat: _galat != null,
                  aktif: !_sedangMendaftar,
                  textInputAction: TextInputAction.done,
                  onChanged: _hapusGalat,
                  onSubmitted: (_) => _daftar(),
                ),
                const SizedBox(height: 8),
                BarisGalatMasuk(galat: _galat),
                const SizedBox(height: 10),
                _TombolDaftar(
                  sibuk: _sedangMendaftar,
                  onPressed: _daftar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol pil oranye berikon (desain). Saat [sibuk]: pudar, jam pasir,
/// "Mendaftarkan...", dan tidak bisa ditekan.
class _TombolDaftar extends StatelessWidget {
  final bool sibuk;
  final VoidCallback onPressed;

  const _TombolDaftar({required this.sibuk, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: sibuk ? 0.6 : 1,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: const Color(0xFFFF8A00),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: sibuk ? null : onPressed,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  sibuk
                      ? Icons.hourglass_top_rounded
                      : Icons.how_to_reg_rounded,
                  size: 22,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  sibuk ? 'Mendaftarkan...' : 'Daftarkan Perangkat',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
