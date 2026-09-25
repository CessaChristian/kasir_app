import 'package:flutter/material.dart';

import '../../../data/perangkat/perangkat_repository.dart';
import '../../../shared/widgets/app_toast.dart';

/// Daftar HP yang boleh menyentuh data toko — hak PATEN pemilik.
///
/// ── KENAPA HALAMAN INI ADA ──
///
/// Mencabut sebuah HP dulu berarti mengganti password akun perangkat, dan itu
/// melempar SEMUA HP sekaligus. Di sini pencabutan mengenai satu HP saja, dan
/// berlaku pada permintaan berikutnya — tidak menunggu tiketnya habis.
///
/// ── KENAPA BUTUH INTERNET ──
///
/// Daftar ini sengaja tidak ikut sinkronisasi. Kalau ikut, keputusan mencabut
/// bisa diambil dari salinan yang basi — dan HP yang baru saja dipulihkan
/// pemilik bisa tercabut lagi oleh salinan lama. Jadi dibaca langsung dari
/// server, apa adanya.
class DaftarPerangkatPage extends StatefulWidget {
  const DaftarPerangkatPage({super.key});

  @override
  State<DaftarPerangkatPage> createState() => _DaftarPerangkatPageState();
}

class _DaftarPerangkatPageState extends State<DaftarPerangkatPage> {
  final _repo = PerangkatRepository.instance;

  List<Perangkat>? _daftar;
  String? _galat;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final d = await _repo.semua();
      if (mounted) {
        setState(() {
          _daftar = d;
          _memuat = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memuat = false;
        _galat = PerangkatRepository.belumDisiapkan(e)
            ? 'Daftar perangkat belum disiapkan di server. Jalankan '
                  'supabase/perangkat.sql lebih dulu.'
            : 'Tidak bisa memuat daftar. Halaman ini butuh internet.';
      });
    }
  }

  Future<void> _gantiNama(Perangkat p) async {
    final c = TextEditingController(text: p.nama);
    final nama = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Nama Perangkat'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama',
            hintText: 'mis. HP Kasir Depan',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (nama == null || nama.isEmpty) return;
    await _jalankan(() => _repo.ubahNama(p.id, nama), 'Nama diperbarui');
  }

  Future<void> _ubahStatus(Perangkat p) async {
    if (p.aktif) {
      final yakin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Cabut ${p.nama}?'),
          content: const Text(
            'HP itu langsung berhenti bisa membaca maupun mengirim data — '
            'tidak perlu menunggu.\n\n'
            'Data yang sudah ada di HP itu tidak terhapus. Bisa dipulihkan '
            'lagi kapan saja dari halaman ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Cabut',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (yakin != true) return;
    }
    await _jalankan(
      () => _repo.ubahStatus(p.id, aktif: !p.aktif),
      p.aktif ? '${p.nama} dicabut' : '${p.nama} dipulihkan',
    );
  }

  Future<void> _lupakan(Perangkat p) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lupakan ${p.nama}?'),
        content: const Text(
          'Barisnya dihapus dari daftar, beserta identitasnya di server.\n\n'
          'Pakai ini untuk HP yang memang sudah tidak ada — rusak, dijual, '
          'atau diganti. Untuk HP yang hilang, biarkan tercabut saja supaya '
          'jejaknya tetap terlihat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Lupakan',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (yakin != true) return;
    await _jalankan(() => _repo.lupakan(p.id), '${p.nama} dilupakan');
  }

  Future<void> _jalankan(Future<void> Function() aksi, String pesan) async {
    try {
      await aksi();
      if (mounted) AppToast.success(context, pesan);
      await _muat();
    } catch (e) {
      if (!mounted) return;
      // Fungsi servernya ditambahkan lewat berkas SQL yang dijalankan pemilik.
      // Kalau berkasnya belum dijalankan ulang, pesan mentah dari PostgREST
      // tidak berarti apa-apa bagi pemilik warung — yang dia butuhkan adalah
      // tahu APA yang harus dilakukan.
      AppToast.error(
        context,
        PerangkatRepository.belumDisiapkan(e)
            ? 'Perlu menjalankan ulang supabase/perangkat.sql di Supabase'
            : 'Gagal: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Perangkat'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _memuat ? null : _muat,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
          ? _pesanKosong(Icons.cloud_off_rounded, _galat!)
          : (_daftar?.isEmpty ?? true)
          ? _pesanKosong(
              Icons.devices_other_rounded,
              'Belum ada perangkat yang terdaftar.',
            )
          // SENGAJA tanpa tarik-untuk-menyegarkan. Gerakan itu di aplikasi
          // ini berarti "jalankan sinkronisasi", sedangkan halaman ini bukan
          // bagian dari sinkronisasi — daftarnya dibaca langsung dari server.
          // Menyeragamkannya justru akan menjalankan sinkron penuh delapan
          // tabel hanya untuk menyegarkan daftar perangkat. Tombol muat ulang
          // ada di kanan atas.
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _daftar!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _kartu(_daftar![i]),
            ),
    );
  }

  Widget _pesanKosong(IconData ikon, String teks) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ikon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            teks,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _kartu(Perangkat p) {
    final warnaStatus = p.aktif ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.smartphone_rounded,
                size: 20,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.nama,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (p.iniSaya)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'HP ini',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warnaStatus.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.aktif ? 'aktif' : 'dicabut',
                  style: TextStyle(fontSize: 11, color: warnaStatus.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Terakhir aktif ${waktuRelatif(p.terakhirAktif)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _gantiNama(p),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Ganti Nama'),
              ),
              // Perangkat ini sendiri sengaja tidak bisa dicabut dari sini:
              // server pun menolaknya. Kalau boleh, pemilik bisa mengunci
              // dirinya keluar hanya dengan satu kali salah pencet.
              if (!p.iniSaya) ...[
                TextButton.icon(
                  onPressed: () => _ubahStatus(p),
                  icon: Icon(
                    p.aktif
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text(p.aktif ? 'Cabut' : 'Pulihkan'),
                ),
                if (!p.aktif)
                  TextButton.icon(
                    onPressed: () => _lupakan(p),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Lupakan'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
