import 'package:flutter/material.dart';
import '../repositories/onboarding_repository.dart';
import '../widgets/owner_setup_step.dart';
import '../../../utils/crypto_utils.dart';
import '../../../data/db.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/recovery/pages/save_recovery_code_page.dart';

class OnboardingPage extends StatefulWidget {
  /// Callback dipanggil setelah onboarding sukses.
  /// Caller (main.dart) handle navigasi ke login.
  final void Function() onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _repo = OnboardingRepository();

  bool _isSubmitting = false;

  /// Setup owner → kedua business (Teras Inn + Thai Tea) di-seed otomatis
  /// dari kode (spec REVISI 2 D3) — tidak ada lagi form business.
  Future<void> _handleOwnerSubmit({
    required String username,
    required String pin,
  }) async {
    setState(() => _isSubmitting = true);

    try {
      // Menggunakan CryptoUtils (PBKDF2-HMAC-SHA256, 120.000 iterasi)
      // — sama dengan pattern di auth_repository.dart + cashier_repository.dart.
      final salt = CryptoUtils.generateSalt();
      final pinHash = CryptoUtils.hashPin(pin, salt);

      final userId = await _repo.setupFirstOwner(
        username: username,
        pinHash: pinHash,
        salt: salt,
      );

      // Recovery code WAJIB ditampilkan sekali di sini — tanpa ini,
      // owner yang lupa PIN tidak akan pernah bisa akses datanya lagi.
      final authRepo = AuthRepository(db);
      final recoveryCode =
          await authRepo.generateAndStoreRecoveryCodeForOwner(userId);

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
        SnackBar(content: Text('Gagal setup: $e')),
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
