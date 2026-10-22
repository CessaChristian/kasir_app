import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/db.dart';
import '../../../../shared/ui/kerangka_masuk.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../utils/crypto_utils.dart';
import '../../../../utils/formatters/recovery_code_formatter.dart';
import '../../repositories/auth_repository.dart';
import '../models/recovery_result.dart';
import 'save_recovery_code_page.dart';
import '../../../../utils/pesan_galat.dart';

/// Reset PIN Owner dengan kode recovery (desain): kode, PIN baru,
/// konfirmasi, galat sebaris di atas tombol "Reset PIN".
///
/// Terlalu banyak kode salah mengunci halaman ini sementara (dihitung
/// [AuthRepository]); hitung mundurnya tampil di galat dan tombol.
class OwnerRecoveryPage extends StatefulWidget {
  /// Diisi test; aplikasi memakai basis data utama.
  final AuthRepository? repo;

  const OwnerRecoveryPage({super.key, this.repo});

  @override
  State<OwnerRecoveryPage> createState() => _OwnerRecoveryPageState();
}

class _OwnerRecoveryPageState extends State<OwnerRecoveryPage> {
  late final _repo = widget.repo ?? AuthRepository(db);
  final _kode = TextEditingController();
  final _pinBaru = TextEditingController();
  final _konfirmasi = TextEditingController();

  var _memuat = false;
  String? _galat;
  int _sisaKunci = 0;
  Timer? _pewaktu;

  bool get _terkunci => _sisaKunci > 0;

  @override
  void initState() {
    super.initState();
    _periksaKunci();
  }

  @override
  void dispose() {
    _kode.dispose();
    _pinBaru.dispose();
    _konfirmasi.dispose();
    _pewaktu?.cancel();
    super.dispose();
  }

  Future<void> _periksaKunci() async {
    final status = await _repo.getOwnerRecoveryLockStatus();
    if (status.isLocked && mounted) _kunci(status.secondsRemaining);
  }

  void _kunci(int detik) {
    setState(() => _sisaKunci = detik);
    _pewaktu?.cancel();
    _pewaktu = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _sisaKunci--;
        if (_sisaKunci <= 0) {
          _sisaKunci = 0;
          _galat = null;
          t.cancel();
        }
      });
    });
  }

  void _hapusGalat(String _) {
    if (_galat != null && !_terkunci) setState(() => _galat = null);
  }

  String? _periksa() {
    if (_kode.text.trim().isEmpty) return 'Kode recovery wajib diisi';
    if (_pinBaru.text.isEmpty) return 'PIN baru wajib diisi';
    if (_pinBaru.text.length != CryptoUtils.pinLength) {
      return 'PIN harus ${CryptoUtils.pinLength} digit';
    }
    if (_konfirmasi.text != _pinBaru.text) return 'PIN tidak cocok';
    return null;
  }

  Future<void> _reset() async {
    if (_terkunci) return;
    final galat = _periksa();
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });

    try {
      final hasil = await _repo.resetOwnerPinWithRecoveryCode(
        recoveryCode: _kode.text.trim(),
        newPin: _pinBaru.text,
      );
      if (!mounted) return;

      if (hasil.isSuccess && hasil.newRecoveryCode != null) {
        AppToast.success(context, 'PIN berhasil direset');
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SaveRecoveryCodePage(
              recoveryCode: hasil.newRecoveryCode!,
              // ctx = context milik SaveRecoveryCodePage, selalu valid
              onComplete: (ctx) {
                Navigator.of(ctx).pop(); // Tutup SaveRecoveryCodePage
                Navigator.of(ctx).pop(); // Tutup halaman ini
              },
            ),
          ),
        );
      } else if (hasil.isLocked) {
        _galat = 'Terlalu banyak percobaan';
        _kunci(hasil.lockSeconds ?? 60);
      } else {
        // Pesan repository berbahasa Inggris untuk log; yang dibaca owner
        // ditulis di sini.
        setState(
          () => _galat = hasil.type == RecoveryResultType.ownerNotFound
              ? 'Akun owner tidak ditemukan di HP ini'
              : 'Kode recovery tidak valid',
        );
        await _periksaKunci();
      }
    } catch (e) {
      if (mounted) setState(() => _galat = pesanGalat(e));
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final galat = _galat != null;
    final aktif = !_terkunci;
    final formatPin = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(CryptoUtils.pinLength),
    ];
    return KerangkaMasuk(
      judul: 'Reset PIN to Access Your',
      onKembali: () => Navigator.pop(context),
      isi: [
        const LabelMasuk('Kode Recovery', atas: 30),
        KolomMasuk(
          controller: _kode,
          ikon: Icons.key_rounded,
          petunjuk: 'XXXX-XXXX-XXXX-XXXX',
          galat: galat,
          aktif: aktif,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            RecoveryCodeFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
          ],
          onChanged: _hapusGalat,
        ),
        const LabelMasuk('PIN Baru'),
        KolomMasuk(
          controller: _pinBaru,
          ikon: Icons.lock_rounded,
          petunjuk: '• • • • • •',
          rahasia: true,
          galat: galat,
          aktif: aktif,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: formatPin,
          onChanged: _hapusGalat,
        ),
        const LabelMasuk('Konfirmasi PIN Baru'),
        KolomMasuk(
          controller: _konfirmasi,
          ikon: Icons.lock_rounded,
          petunjuk: '• • • • • •',
          rahasia: true,
          galat: galat,
          aktif: aktif,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: formatPin,
          onChanged: _hapusGalat,
          onSubmitted: (_) => _reset(),
        ),
        const JarakMasuk(14),
        BarisGalatMasuk(
          galat: _terkunci
              ? 'Terlalu banyak percobaan. Tunggu $_sisaKunci detik.'
              : _galat,
        ),
        const JarakMasuk(20),
        TombolMasuk(
          label: _terkunci
              ? 'Tunggu $_sisaKunci detik…'
              : _memuat
              ? 'Memeriksa…'
              : 'Reset PIN',
          onPressed: _memuat || _terkunci ? null : _reset,
        ),
      ],
    );
  }
}
