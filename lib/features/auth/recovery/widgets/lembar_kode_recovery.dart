import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/db.dart';
import '../../../../shared/ui/teks_teras.dart';
import '../../../../shared/ui/warna_teras.dart';
import '../../../../utils/crypto_utils.dart';
import '../../repositories/auth_repository.dart';
import '../pages/save_recovery_code_page.dart';

/// Alur "Kode Recovery" di Profil (desain): lembar "Perbarui Kode Recovery"
/// meminta PIN saat ini, lalu halaman kode baru yang hanya tampil sekali.
Future<void> perbaruiKodeRecovery(BuildContext context) async {
  final kode = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WarnaTeras.kartu,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LembarPerbaruiRecovery(authRepo: AuthRepository(db)),
  );
  if (kode == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SaveRecoveryCodePage(
        recoveryCode: kode,
        onComplete: (ctx) => Navigator.pop(ctx),
      ),
    ),
  );
}

/// Lembar "Perbarui Kode Recovery". Menutup diri dengan kode baru kalau PIN
/// benar; PIN salah ditampilkan di dalam lembar supaya bisa dicoba lagi.
class LembarPerbaruiRecovery extends StatefulWidget {
  final AuthRepository authRepo;

  const LembarPerbaruiRecovery({super.key, required this.authRepo});

  @override
  State<LembarPerbaruiRecovery> createState() => _LembarPerbaruiRecoveryState();
}

class _LembarPerbaruiRecoveryState extends State<LembarPerbaruiRecovery> {
  final _pinC = TextEditingController();
  var _sembunyi = true;
  var _memproses = false;
  String? _galat;

  @override
  void dispose() {
    _pinC.dispose();
    super.dispose();
  }

  Future<void> _buat() async {
    if (_memproses) return;
    if (_pinC.text.length != CryptoUtils.pinLength) {
      setState(() => _galat = 'PIN harus ${CryptoUtils.pinLength} angka');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      final res = await widget.authRepo.regenerateOwnerRecoveryCode(_pinC.text);
      if (!mounted) return;
      if (res.isSuccess && res.newRecoveryCode != null) {
        Navigator.pop(context, res.newRecoveryCode);
        return;
      }
      setState(() {
        _memproses = false;
        _galat = res.message ?? 'PIN salah';
        _pinC.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _memproses = false;
          _galat = 'Gagal membuat kode: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: WarnaTeras.oranyeMuda,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.key_rounded,
                size: 30,
                color: WarnaTeras.oranye,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Perbarui Kode Recovery',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TeksTeras.judulBagian,
              fontWeight: FontWeight.w700,
              color: WarnaTeras.teks,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Masukkan PIN saat ini untuk membuat kode recovery baru.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              color: WarnaTeras.teksPudar,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'PIN Saat Ini',
            style: TextStyle(
              fontSize: TeksTeras.biasa,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A5048),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: _galat != null
                    ? const Color(0xFFE0828A)
                    : const Color(0xFFDDD6CF),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 22,
                  color: WarnaTeras.teksPudar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('isian-pin-recovery'),
                    controller: _pinC,
                    autofocus: true,
                    obscureText: _sembunyi,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(CryptoUtils.pinLength),
                    ],
                    onChanged: (_) => setState(() => _galat = null),
                    onSubmitted: (_) => _buat(),
                    style: const TextStyle(
                      fontSize: TeksTeras.angka,
                      letterSpacing: 4,
                    ),
                    decoration: const InputDecoration(
                      hintText: '• • • • • •',
                      hintStyle: TextStyle(color: Color(0xFFB5ADA6)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _sembunyi ? 'Tampilkan PIN' : 'Sembunyikan PIN',
                  onPressed: () => setState(() => _sembunyi = !_sembunyi),
                  icon: Icon(
                    _sembunyi
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 22,
                    color: WarnaTeras.teksSamar,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 26,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _galat ?? '',
                style: const TextStyle(
                  fontSize: TeksTeras.kecil,
                  color: WarnaTeras.merah,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5A5048),
                      side: const BorderSide(color: Color(0xFFDDD6CF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 16,
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _memproses ? null : _buat,
                    style: FilledButton.styleFrom(
                      backgroundColor: WarnaTeras.oranye,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _memproses ? 'Memproses…' : 'Buat Kode Baru',
                      style: const TextStyle(
                        fontSize: TeksTeras.biasa,
                        fontWeight: FontWeight.w600,
                      ),
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
}
