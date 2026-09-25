import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../data/supabase/supabase_service.dart';

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

  const DaftarkanPerangkatPage({
    super.key,
    required this.sesudahBerhasil,
    this.lengkapiSaja = false,
  });

  @override
  State<DaftarkanPerangkatPage> createState() => _DaftarkanPerangkatPageState();
}

class _DaftarkanPerangkatPageState extends State<DaftarkanPerangkatPage> {
  final _kunciC = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _sedangMendaftar = false;
  bool _kunciTerlihat = false;
  String? _galat;

  @override
  void dispose() {
    _kunciC.dispose();
    super.dispose();
  }

  Future<void> _daftar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sedangMendaftar = true;
      _galat = null;
    });

    // Identitas dibuat hanya kalau HP ini memang belum punya. Yang sudah punya
    // cukup dicatatkan — membuat identitas baru berarti meninggalkan yang lama
    // sebagai baris yatim di daftar pengguna server.
    if (!widget.lengkapiSaja) {
      final hasil = await SupabaseService.instance.buatIdentitasBaru();
      if (!mounted) return;
      if (hasil != HasilDaftarPerangkat.berhasil) {
        setState(() {
          _sedangMendaftar = false;
          _galat = hasil == HasilDaftarPerangkat.jaringan
              ? 'Tidak bisa menghubungi server. Pendaftaran perangkat butuh '
                    'internet — periksa koneksi lalu coba lagi.'
              : 'Pendaftaran gagal. Coba lagi sebentar lagi.';
        });
        return;
      }
    }

    // Di sinilah kuncinya benar-benar diperiksa, oleh server.
    final diterima = await PerangkatRepository.instance.daftarkanIdentitasIni(
      _kunciC.text,
    );
    if (!mounted) return;

    if (!diterima) {
      // Identitas yang tidak diakui siapa pun jangan ditinggalkan menggantung.
      if (!widget.lengkapiSaja) {
        await SupabaseService.instance.lepaskanPerangkat();
      }
      if (!mounted) return;
      setState(() {
        _sedangMendaftar = false;
        _galat = 'Kunci pemasangan salah. Periksa lagi kuncinya.';
      });
      return;
    }

    await _beriTahuBerhasil();
    if (!mounted) return;
    await widget.sesudahBerhasil();
  }

  /// Beri tahu pemilik bahwa HP ini sudah tercatat, dan dengan nama apa.
  ///
  /// Ditampilkan sebagai dialog, bukan pesan sekilas: layar ini langsung
  /// berpindah setelahnya, dan pesan sekilas akan ikut hilang sebelum sempat
  /// terbaca. Namanya disebut supaya pemilik tahu baris mana yang barusan
  /// muncul di daftar — dan bisa langsung menggantinya kalau perlu.
  Future<void> _beriTahuBerhasil() async {
    final nama = await PerangkatRepository.instance.tebakNama();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.check_circle_rounded,
          color: Colors.green.shade400,
          size: 40,
        ),
        title: const Text('Perangkat Terdaftar'),
        content: SizedBox(
          width: double.maxFinite,
          child: Text(
            'Nama perangkat: $nama\n\n'
            'HP ini sudah boleh menyentuh data toko.',
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warna = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: warna.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.key_rounded, size: 40, color: warna),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.lengkapiSaja
                        ? 'Lengkapi Pendaftaran'
                        : 'Daftarkan Perangkat',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.lengkapiSaja
                        ? 'Masukkan kunci pemasangan dari pemilik untuk '
                              'menghubungkan HP ini ke data toko. Data di HP '
                              'ini tidak berubah.'
                        : 'HP ini belum terdaftar. Masukkan kunci pemasangan '
                              'dari pemilik untuk menghubungkannya ke data toko.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _kunciC,
                    enabled: !_sedangMendaftar,
                    obscureText: !_kunciTerlihat,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Kunci pemasangan',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _kunciTerlihat
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed: () =>
                            setState(() => _kunciTerlihat = !_kunciTerlihat),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Kunci belum diisi' : null,
                  ),
                  if (_galat != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _galat!,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _sedangMendaftar ? null : _daftar,
                    icon: _sedangMendaftar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.how_to_reg_rounded),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _sedangMendaftar
                            ? 'Mendaftarkan…'
                            : 'Daftarkan Perangkat',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
