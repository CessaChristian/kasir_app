import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/constants/app_constants.dart';
import '../../../../shared/ui/kartu_teras.dart';
import '../../../../shared/ui/teks_teras.dart';
import '../../../../shared/ui/warna_teras.dart';
import '../../../../shared/widgets/app_toast.dart';

/// Page to display recovery code (SHOW ONLY ONCE!)
///
/// User must save the code before proceeding
class SaveRecoveryCodePage extends StatefulWidget {
  final String recoveryCode;
  // Context dari halaman ini dikirim ke callback agar navigasi selalu pakai
  // context yang valid — bukan context parent yang bisa jadi sudah stale
  // setelah pushReplacement.
  final void Function(BuildContext context) onComplete;

  const SaveRecoveryCodePage({
    super.key,
    required this.recoveryCode,
    required this.onComplete,
  });

  @override
  State<SaveRecoveryCodePage> createState() => _SaveRecoveryCodePageState();
}

class _SaveRecoveryCodePageState extends State<SaveRecoveryCodePage> {
  bool _hasAccepted = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryCode));

    if (!mounted) return;
    AppToast.success(
      context,
      'Kode disalin. Clipboard otomatis dihapus dalam 30 detik',
    );

    // S14: Auto-clear clipboard setelah 30 detik agar tidak terbaca
    // oleh app lain atau ter-paste tidak sengaja di tempat lain.
    Future.delayed(const Duration(seconds: 30), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == widget.recoveryCode) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  /// Kode dipecah per 4 huruf supaya mudah dibaca dan disalin ke kertas.
  String get _kodeTampil {
    final k = widget.recoveryCode.replaceAll('-', '');
    return [
      for (var i = 0; i < k.length; i += 4)
        k.substring(i, i + 4 > k.length ? k.length : i + 4),
    ].join('-');
  }

  @override
  Widget build(BuildContext context) {
    // Sengaja tanpa tombol kembali (desain punya ←): kode hanya tampil
    // SEKALI, jadi halaman baru boleh ditinggal setelah pemilik mencentang
    // bahwa kodenya sudah disimpan.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: WarnaTeras.latar,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(
                height: 52,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Kode Recovery',
                      style: TextStyle(
                        fontSize: TeksTeras.judul,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  children: [
                    _kartuKode(),
                    const SizedBox(height: 12),
                    _peringatan(),
                    const SizedBox(height: 12),
                    _saran(),
                    const SizedBox(height: 12),
                    _centang(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _hasAccepted
                        ? () => widget.onComplete(context)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: WarnaTeras.oranye,
                      disabledBackgroundColor: const Color(0xFFEDE5DD),
                      disabledForegroundColor: WarnaTeras.teksSamar,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Saya Mengerti, Lanjutkan',
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartuKode() {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: WarnaTeras.oranye,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -46,
            top: -48,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.key_rounded,
                      size: 21,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Expanded: huruf yang diperbesar tidak boleh tumpah.
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kode Recovery Owner',
                          style: TextStyle(
                            fontSize: TeksTeras.biasa,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          AppConstants.storeName,
                          style: TextStyle(
                            fontSize: TeksTeras.kecil,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SelectableText(
                    _kodeTampil,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: WarnaTeras.teks,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: const Text(
                    'Salin kode',
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

  Widget _peringatan() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        border: Border.all(color: const Color(0xFFF3D9A4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_rounded, size: 21, color: Color(0xFFC98500)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hanya ditampilkan sekali',
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B4A00),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Simpan kode ini di tempat yang aman sebelum melanjutkan. '
                  'Kode lama sudah tidak berlaku.',
                  style: TextStyle(
                    fontSize: TeksTeras.kecil,
                    height: 1.45,
                    color: Color(0xFF6B5A3A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saran() {
    Widget baris(IconData ikon, String teks) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(ikon, size: 18, color: WarnaTeras.oranye),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              teks,
              style: const TextStyle(
                fontSize: TeksTeras.kecil,
                color: Color(0xFF5A5048),
              ),
            ),
          ),
        ],
      ),
    );
    return KartuTeras(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saran penyimpanan',
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teksSedang,
            ),
          ),
          baris(Icons.password_rounded, 'Password manager'),
          baris(Icons.lock_rounded, 'Catatan terkunci di perangkat Owner'),
          baris(
            Icons.edit_note_rounded,
            'Tulis di kertas, simpan di tempat offline',
          ),
        ],
      ),
    );
  }

  Widget _centang() {
    return Material(
      color: WarnaTeras.kartu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _hasAccepted ? WarnaTeras.oranye : WarnaTeras.garis,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _hasAccepted = !_hasAccepted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _hasAccepted ? WarnaTeras.oranye : Colors.transparent,
                  border: Border.all(
                    color: _hasAccepted
                        ? WarnaTeras.oranye
                        : WarnaTeras.titikPasif,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _hasAccepted
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Saya sudah menyimpan kode recovery dengan aman',
                  style: TextStyle(
                    fontSize: TeksTeras.biasa,
                    fontWeight: FontWeight.w600,
                    color: WarnaTeras.teksSedang,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
