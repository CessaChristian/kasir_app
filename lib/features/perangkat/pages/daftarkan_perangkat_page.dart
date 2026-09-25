import 'package:flutter/material.dart';

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

  const DaftarkanPerangkatPage({super.key, required this.sesudahBerhasil});

  @override
  State<DaftarkanPerangkatPage> createState() => _DaftarkanPerangkatPageState();
}

class _DaftarkanPerangkatPageState extends State<DaftarkanPerangkatPage> {
  final _emailC = TextEditingController();
  final _kunciC = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _sedangMendaftar = false;
  bool _kunciTerlihat = false;
  String? _galat;

  @override
  void dispose() {
    _emailC.dispose();
    _kunciC.dispose();
    super.dispose();
  }

  Future<void> _daftar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sedangMendaftar = true;
      _galat = null;
    });

    final hasil = await SupabaseService.instance.daftarkanDenganKunci(
      email: _emailC.text.trim(),
      password: _kunciC.text,
    );

    if (!mounted) return;

    if (hasil == HasilDaftarPerangkat.berhasil) {
      await widget.sesudahBerhasil();
      return;
    }

    setState(() {
      _sedangMendaftar = false;
      _galat = switch (hasil) {
        HasilDaftarPerangkat.kunciSalah =>
          'Kunci pemasangan salah. Periksa lagi email dan kuncinya.',
        HasilDaftarPerangkat.jaringan =>
          'Tidak bisa menghubungi server. Pendaftaran perangkat butuh '
              'internet — periksa koneksi lalu coba lagi.',
        _ => 'Pendaftaran gagal. Coba lagi sebentar lagi.',
      };
    });
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
                  const Text(
                    'Daftarkan Perangkat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'HP ini belum terdaftar. Masukkan kunci pemasangan dari '
                    'pemilik untuk menghubungkannya ke data toko.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailC,
                    enabled: !_sedangMendaftar,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email pemasangan',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Email belum diisi'
                        : null,
                  ),
                  const SizedBox(height: 14),
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
