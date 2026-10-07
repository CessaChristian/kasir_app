import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_database.dart';
import '../../../shared/ui/inisial_akun.dart';
import '../../../shared/ui/kolom_lembar.dart';
import '../../../shared/ui/lembar_bawah.dart';
import '../../../shared/ui/teks_teras.dart';
import '../../../shared/ui/tombol_lembar.dart';
import '../../../shared/ui/warna_teras.dart';
import '../../../utils/crypto_utils.dart';
import '../repositories/cashier_repository.dart';

/// Isian PIN: hanya angka, sepanjang [CryptoUtils.pinLength].
final _formatPin = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(CryptoUtils.pinLength),
];

/// Pesan di bawah dua isian PIN (desain): kosong selama belum diisi,
/// "PIN harus 6 digit angka", "PIN belum cocok", atau "PIN cocok".
/// Mengembalikan (pesan, cocok); pesan null = belum ada yang perlu dikatakan.
(String?, bool) periksaPinBaru(String pin, String ulang) {
  final panjang = CryptoUtils.pinLength;
  if (pin.isEmpty && ulang.isEmpty) return (null, false);
  if (pin.length != panjang) return ('PIN harus $panjang digit angka', false);
  if (ulang.isEmpty) return (null, false);
  if (ulang != pin) return ('PIN belum cocok', false);
  return ('PIN cocok', true);
}

/// Galat username (desain Tambah Akun / Ubah Username); null = sah.
String? periksaUsername(String nama) {
  final n = nama.trim();
  if (n.isEmpty) return 'Username wajib diisi';
  if (n.length < CashierRepository.panjangNamaMin ||
      n.length > CashierRepository.panjangNamaMaks) {
    return 'Username harus ${CashierRepository.panjangNamaMin}–'
        '${CashierRepository.panjangNamaMaks} karakter';
  }
  return null;
}

String _pesanGalat(Object e) => switch (e) {
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => 'Gagal menyimpan: $e',
};

Widget _tombolMata(bool tampil, VoidCallback onTap) => IconButton(
  onPressed: onTap,
  tooltip: tampil ? 'Sembunyikan PIN' : 'Lihat PIN',
  visualDensity: VisualDensity.compact,
  icon: Icon(
    tampil ? Icons.visibility_off_rounded : Icons.visibility_rounded,
    size: 21,
    color: WarnaTeras.teksSamar,
  ),
);

Widget _pesanPin(String? pesan, bool cocok) => SizedBox(
  height: 22,
  child: pesan == null
      ? null
      : Row(
          children: [
            Icon(
              cocok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 16,
              color: cocok ? WarnaTeras.hijau : WarnaTeras.merah,
            ),
            const SizedBox(width: 4),
            Text(
              pesan,
              style: TextStyle(
                fontSize: TeksTeras.kecil,
                color: cocok ? WarnaTeras.hijau : WarnaTeras.merah,
              ),
            ),
          ],
        ),
);

// ---------------------------------------------------------------------------
// Tambah Akun Kasir
// ---------------------------------------------------------------------------

/// Lembar "Tambah Akun Kasir" (desain). True = akun dibuat.
Future<bool> tampilkanTambahKasir(
  BuildContext context,
  CashierRepository repo,
) async {
  final hasil = await tampilkanLembarBawah<bool>(
    context,
    (_) => _TambahKasir(repo: repo),
  );
  return hasil == true;
}

class _TambahKasir extends StatefulWidget {
  final CashierRepository repo;

  const _TambahKasir({required this.repo});

  @override
  State<_TambahKasir> createState() => _TambahKasirState();
}

class _TambahKasirState extends State<_TambahKasir> {
  final _nama = TextEditingController();
  final _pin = TextEditingController();
  final _ulang = TextEditingController();
  var _tampil = false;
  var _menyimpan = false;
  String? _galat;

  @override
  void dispose() {
    _nama.dispose();
    _pin.dispose();
    _ulang.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final galatNama = periksaUsername(_nama.text);
    final (pesanPin, cocok) = periksaPinBaru(_pin.text, _ulang.text);
    final galat =
        galatNama ?? (cocok ? null : pesanPin ?? 'Isi PIN dan konfirmasinya');
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    setState(() {
      _menyimpan = true;
      _galat = null;
    });
    try {
      await widget.repo.createCashier(
        username: _nama.text.trim(),
        pin: _pin.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _menyimpan = false;
          _galat = _pesanGalat(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (_, cocok) = periksaPinBaru(_pin.text, _ulang.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JudulLembar(
          judul: 'Tambah Akun Kasir',
          keterangan: 'Kasir login memakai username dan PIN ini.',
        ),
        const SizedBox(height: 18),
        KolomLembar(
          label: 'Username',
          controller: _nama,
          ikon: Icons.person_rounded,
          petunjuk: 'contoh: sari',
          onChanged: (_) => setState(() => _galat = null),
        ),
        const SizedBox(height: 12),
        KolomLembar(
          label: 'PIN (${CryptoUtils.pinLength} digit)',
          controller: _pin,
          ikon: Icons.lock_rounded,
          sembunyikan: !_tampil,
          keyboardType: TextInputType.number,
          inputFormatters: _formatPin,
          onChanged: (_) => setState(() => _galat = null),
          akhiran: _tombolMata(
            _tampil,
            () => setState(() => _tampil = !_tampil),
          ),
        ),
        const SizedBox(height: 12),
        KolomLembar(
          label: 'Konfirmasi PIN',
          controller: _ulang,
          ikon: Icons.lock_reset_rounded,
          sembunyikan: !_tampil,
          keyboardType: TextInputType.number,
          inputFormatters: _formatPin,
          onChanged: (_) => setState(() => _galat = null),
          akhiran: cocok
              ? const Icon(
                  Icons.check_circle_rounded,
                  size: 21,
                  color: WarnaTeras.hijau,
                )
              : null,
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 18),
          margin: const EdgeInsets.only(top: 10),
          child: Text(
            _galat ?? '',
            style: const TextStyle(
              fontSize: TeksTeras.kecil,
              color: WarnaTeras.merah,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 10,
              child: TombolLembar(
                label: 'Batal',
                latar: WarnaTeras.latarAbu,
                warna: WarnaTeras.teks,
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 14,
              child: TombolLembar(
                label: _menyimpan ? 'Menyimpan…' : 'Simpan Akun',
                latar: WarnaTeras.oranye,
                warna: Colors.white,
                onPressed: _menyimpan ? null : _simpan,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Menu akun (⋮)
// ---------------------------------------------------------------------------

/// Lembar ⋮ (desain): kepala akun, Ubah Username, Hapus Akun.
///
/// Hapus Akun SENGAJA belum berfungsi — tampil sesuai desain tapi diketuk
/// tidak melakukan apa-apa. Keputusan "satu akun = satu orang, tanpa hapus"
/// sedang dibuka lagi bersama owner (2026-10-07). True = pilih Ubah Username.
Future<bool> tampilkanMenuAkun(BuildContext context, User akun) async {
  final hasil = await tampilkanLembarBawah<bool>(
    context,
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: WarnaTeras.garis)),
          ),
          child: Row(
            children: [
              InisialKasir(nama: akun.username, ukuran: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      akun.username,
                      style: const TextStyle(
                        fontSize: TeksTeras.judulBagian,
                        fontWeight: FontWeight.w700,
                        color: WarnaTeras.teks,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _pilihanMenu(
          ikon: Icons.edit_rounded,
          judul: 'Ubah Username',
          keterangan: 'Dipakai kasir untuk login',
          warna: WarnaTeras.oranye,
          latar: WarnaTeras.oranyeMuda,
          onTap: () => Navigator.pop(context, true),
        ),
        _pilihanMenu(
          ikon: Icons.delete_rounded,
          judul: 'Hapus Akun',
          keterangan: 'Akun tidak bisa dipakai lagi',
          warna: WarnaTeras.merah,
          latar: WarnaTeras.merahMuda,
          warnaJudul: WarnaTeras.merah,
          onTap: () {},
        ),
      ],
    ),
  );
  return hasil == true;
}

Widget _pilihanMenu({
  required IconData ikon,
  required String judul,
  required String keterangan,
  required Color warna,
  required Color latar,
  required VoidCallback onTap,
  Color warnaJudul = WarnaTeras.teks,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: latar,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(ikon, size: 21, color: warna),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  style: TextStyle(
                    fontSize: TeksTeras.menu,
                    fontWeight: FontWeight.w600,
                    color: warnaJudul,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  keterangan,
                  style: const TextStyle(
                    fontSize: TeksTeras.kecil,
                    color: WarnaTeras.teksPudar,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: WarnaTeras.titikPasif),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Ubah Username
// ---------------------------------------------------------------------------

/// Lembar "Ubah Username" (desain). True = tersimpan.
Future<bool> tampilkanUbahUsername(
  BuildContext context,
  CashierRepository repo,
  User akun,
) async {
  final hasil = await tampilkanLembarBawah<bool>(
    context,
    (_) => _UbahUsername(repo: repo, akun: akun),
  );
  return hasil == true;
}

class _UbahUsername extends StatefulWidget {
  final CashierRepository repo;
  final User akun;

  const _UbahUsername({required this.repo, required this.akun});

  @override
  State<_UbahUsername> createState() => _UbahUsernameState();
}

class _UbahUsernameState extends State<_UbahUsername> {
  late final _nama = TextEditingController(text: widget.akun.username);
  var _menyimpan = false;

  /// Galat dari server/database (nama sudah dipakai, tidak bisa dicek).
  String? _galatSimpan;

  @override
  void dispose() {
    _nama.dispose();
    super.dispose();
  }

  bool get _berubah => _nama.text.trim() != widget.akun.username;

  Future<void> _simpan() async {
    setState(() {
      _menyimpan = true;
      _galatSimpan = null;
    });
    try {
      await widget.repo.gantiNamaKasir(widget.akun.id, _nama.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _menyimpan = false;
          _galatSimpan = _pesanGalat(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final galat = _galatSimpan ?? periksaUsername(_nama.text);
    final petunjuk =
        galat ??
        (_berubah
            ? 'Username baru dipakai saat login berikutnya'
            : 'Sama dengan username sekarang');
    final bolehSimpan = galat == null && _berubah && !_menyimpan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KepalaLembarIkon(
          ikon: Icons.badge_rounded,
          judul: 'Ubah Username',
          keterangan: 'Kasir login dengan username baru. PIN tidak berubah.',
        ),
        const SizedBox(height: 18),
        KolomLembar(
          label: 'Username',
          controller: _nama,
          awalan: '@',
          petunjuk: 'username',
          galat: galat != null,
          autofocus: true,
          onChanged: (_) => setState(() => _galatSimpan = null),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 18),
          margin: const EdgeInsets.only(top: 6),
          child: Text(
            petunjuk,
            style: TextStyle(
              fontSize: TeksTeras.kecil,
              color: galat != null ? WarnaTeras.merah : WarnaTeras.teksPudar,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _tombolBawah(
          context,
          labelSimpan: _menyimpan ? 'Memeriksa…' : 'Simpan',
          onSimpan: bolehSimpan ? _simpan : null,
        ),
      ],
    );
  }
}

/// [Batal] bergaris + [Simpan] (desain lembar Ubah Username dan Reset PIN).
Widget _tombolBawah(
  BuildContext context, {
  required String labelSimpan,
  required VoidCallback? onSimpan,
}) {
  return Row(
    children: [
      Expanded(
        flex: 10,
        child: TombolLembar(
          label: 'Batal',
          latar: WarnaTeras.kartu,
          warna: const Color(0xFF5A5048),
          tepi: const Color(0xFFDDD6CF),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 14,
        child: TombolLembar(
          label: labelSimpan,
          latar: WarnaTeras.oranye,
          warna: Colors.white,
          onPressed: onSimpan,
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Reset PIN
// ---------------------------------------------------------------------------

/// Lembar "Reset PIN" (desain). True = PIN baru tersimpan.
Future<bool> tampilkanResetPin(
  BuildContext context,
  CashierRepository repo,
  User akun,
) async {
  final hasil = await tampilkanLembarBawah<bool>(
    context,
    (_) => _ResetPin(repo: repo, akun: akun),
  );
  return hasil == true;
}

class _ResetPin extends StatefulWidget {
  final CashierRepository repo;
  final User akun;

  const _ResetPin({required this.repo, required this.akun});

  @override
  State<_ResetPin> createState() => _ResetPinState();
}

class _ResetPinState extends State<_ResetPin> {
  final _pin = TextEditingController();
  final _ulang = TextEditingController();
  var _tampil = false;
  var _menyimpan = false;
  String? _galatSimpan;

  @override
  void dispose() {
    _pin.dispose();
    _ulang.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    setState(() {
      _menyimpan = true;
      _galatSimpan = null;
    });
    try {
      await widget.repo.resetCashierPin(widget.akun.id, _pin.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _menyimpan = false;
          _galatSimpan = _pesanGalat(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (pesan, cocok) = periksaPinBaru(_pin.text, _ulang.text);
    final mata = _tombolMata(_tampil, () => setState(() => _tampil = !_tampil));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KepalaLembarIkon(
          ikon: Icons.lock_reset_rounded,
          judul: 'Reset PIN ${widget.akun.username}',
          keterangan:
              'Masukkan PIN baru untuk akun ini. PIN lama tidak bisa dipakai '
              'lagi.',
        ),
        const SizedBox(height: 14),
        KolomLembar(
          label: 'PIN Baru',
          controller: _pin,
          ikon: Icons.lock_rounded,
          sembunyikan: !_tampil,
          keyboardType: TextInputType.number,
          inputFormatters: _formatPin,
          onChanged: (_) => setState(() => _galatSimpan = null),
          akhiran: mata,
        ),
        const SizedBox(height: 14),
        KolomLembar(
          label: 'Konfirmasi PIN Baru',
          controller: _ulang,
          ikon: Icons.lock_rounded,
          sembunyikan: !_tampil,
          galat: pesan == 'PIN belum cocok',
          keyboardType: TextInputType.number,
          inputFormatters: _formatPin,
          onChanged: (_) => setState(() => _galatSimpan = null),
          akhiran: mata,
        ),
        const SizedBox(height: 6),
        _galatSimpan == null
            ? _pesanPin(pesan, cocok)
            : _pesanPin(_galatSimpan, false),
        const SizedBox(height: 12),
        _tombolBawah(
          context,
          labelSimpan: _menyimpan ? 'Menyimpan…' : 'Simpan PIN',
          onSimpan: cocok && !_menyimpan ? _simpan : null,
        ),
      ],
    );
  }
}
