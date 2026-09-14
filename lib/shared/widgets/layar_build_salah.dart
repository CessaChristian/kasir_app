import 'package:flutter/material.dart';

/// Layar penghenti untuk APK yang dibangun tanpa kredensial perangkat.
///
/// ── KENAPA MENGHENTIKAN, BUKAN SEKADAR MEMPERINGATKAN ──
///
/// Tanpa kredensial perangkat, aplikasi tidak pernah bisa login ke server.
/// Ia tetap berjalan mulus — kasir bisa berjualan, owner bisa membuat akun —
/// tapi tidak satu baris pun pernah terkirim ke mana-mana.
///
/// Kegagalan itu tidak menimbulkan apa pun di layar, dan baru ketahuan
/// berhari-hari kemudian saat pemilik membuka HP-nya sendiri dan menemukannya
/// kosong. Saat itu sudah ada seminggu penjualan yang hanya ada di satu HP.
///
/// Peringatan yang bisa ditutup tidak cukup: yang memasang APK ke HP klien
/// belum tentu orang yang memperhatikan layarnya. Menghentikan aplikasi
/// memindahkan kegagalannya dari "ketahuan seminggu kemudian" menjadi
/// "ketahuan detik pertama", dan itu satu-satunya waktu ketika memperbaikinya
/// masih murah.
///
/// Hanya muncul di build RELEASE. Build debug tanpa kredensial memang wajar —
/// berguna saat menggarap tampilan tanpa perlu server.
///
/// ── KENAPA TIDAK MENAMPILKAN PERINTAH BUILD ──
///
/// Layar ini muncul di build RELEASE, yaitu APK yang sudah dikemas untuk
/// dipasang di HP orang. Kalau sampai ke tangan pemilik warung atau kasir,
/// menampilkan `flutter build apk --dart-define=...` tidak menolong mereka
/// sama sekali — mereka tidak punya kode sumbernya, dan tidak seharusnya
/// diminta mengerti perintah itu.
///
/// Yang berguna bagi mereka hanya dua hal: jangan dipakai, dan hubungi siapa.
/// Perinciannya urusan yang membangun APK-nya, dan orang itu sudah tahu di
/// mana mencarinya.
class LayarBuildSalah extends StatelessWidget {
  const LayarBuildSalah({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF7F1D1D),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 72, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    'APK Ini Salah Build',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aplikasi ini tidak bisa terhubung ke server, jadi seluruh '
                    'penjualan hanya akan tersimpan di HP ini dan tidak pernah '
                    'terkirim ke mana pun.\n\n'
                    'Jangan dipakai. Hubungi pembuat aplikasi untuk meminta '
                    'versi yang benar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.white70,
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
