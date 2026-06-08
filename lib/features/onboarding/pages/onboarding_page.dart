import 'package:flutter/material.dart';
import '../repositories/onboarding_repository.dart';
import '../widgets/owner_setup_step.dart';
import '../widgets/business_setup_step.dart';
import '../../../utils/crypto_utils.dart';

class OnboardingPage extends StatefulWidget {
  /// Callback dipanggil setelah onboarding sukses dengan businessId baru.
  /// Caller (main.dart) handle navigasi ke dashboard + load BusinessContext.
  final void Function(String businessId) onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  final _repo = OnboardingRepository();

  // Step 1 data
  String? _username;
  String? _pin;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handleOwnerSubmit({required String username, required String pin}) {
    setState(() {
      _username = username;
      _pin = pin;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleBusinessSubmit({
    required String name,
    required String type,
    String? address,
    String? phone,
  }) async {
    if (_username == null || _pin == null) return;

    setState(() => _isSubmitting = true);

    try {
      // Menggunakan CryptoUtils (PBKDF2-HMAC-SHA256, 120.000 iterasi)
      // — sama dengan pattern di auth_repository.dart + cashier_repository.dart.
      final salt = CryptoUtils.generateSalt();
      final pinHash = CryptoUtils.hashPin(_pin!, salt);

      final businessId = await _repo.setupFirstOwnerAndBusiness(
        username: _username!,
        pinHash: pinHash,
        salt: salt,
        businessName: name,
        businessType: type,
        businessAddress: address,
        businessPhone: phone,
      );

      if (!mounted) return;
      widget.onComplete(businessId);
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
          : PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                OwnerSetupStep(onSubmit: _handleOwnerSubmit),
                BusinessSetupStep(
                  onSubmit: ({
                    required name,
                    required type,
                    address,
                    phone,
                  }) =>
                      _handleBusinessSubmit(
                          name: name, type: type, address: address, phone: phone),
                  onBack: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),
              ],
            ),
    );
  }
}
