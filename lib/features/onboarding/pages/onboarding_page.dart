import 'package:flutter/material.dart';
import '../widgets/owner_setup_step.dart';
import '../../../data/db.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/recovery/pages/save_recovery_code_page.dart';
import '../../../utils/pesan_galat.dart';

class OnboardingPage extends StatefulWidget {
  /// Callback dipanggil setelah onboarding sukses.
  /// Caller (main.dart) handle navigasi ke login.
  final void Function() onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {

  bool _isSubmitting = false;

  /// Setup akun owner — satu-satunya langkah onboarding.
  Future<void> _handleOwnerSubmit({
    required String username,
    required String pin,
  }) async {
    setState(() => _isSubmitting = true);

    try {
      // Akun + kode recovery dalam satu transaksi, lewat aturan yang sama
      // dengan halaman setup owner (cek owner sudah ada, aturan username).
      // Recovery code WAJIB ditampilkan sekali di sini — tanpa ini,
      // owner yang lupa PIN tidak akan pernah bisa akses datanya lagi.
      final (owner: _, kodeRecovery: recoveryCode) = await AuthRepository(
        db,
      ).buatOwnerPertama(username: username, pin: pin);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaveRecoveryCodePage(
            recoveryCode: recoveryCode,
            // ctx milik SaveRecoveryCodePage — selalu valid saat dipanggil
            onComplete: (_) => widget.onComplete(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pesanGalat(e, awalan: 'Gagal menyiapkan aplikasi')),
        ),
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Aplikasi'),
        automaticallyImplyLeading: false,
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : OwnerSetupStep(onSubmit: _handleOwnerSubmit),
    );
  }
}
