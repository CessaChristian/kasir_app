import 'package:flutter/material.dart';

/// Lebar acuan tampilan: semua halaman disetel di layar 411 dp (Pixel 8a).
const lebarAcuan = 411.0;

/// Pengecilan paling banyak — di bawah ini tulisan dan tombol terlalu mungil.
const skalaMin = 0.85;

/// Skala gambar untuk layar selebar [lebar] dp: 1 untuk layar selebar acuan
/// atau lebih, lebih kecil untuk layar sempit (360 dp → ±0,876).
double skalaUntukLebar(double lebar) =>
    lebar <= 0 ? 1 : (lebar / lebarAcuan).clamp(skalaMin, 1.0);

/// Membuat layar sempit menampilkan tata letak yang SAMA dengan layar acuan.
///
/// Flutter mengukur dalam dp, dan banyak HP Android (density 480, mis.
/// Realme RMX3085) hanya selebar 360 dp — semua elemen jadi ±14% lebih besar
/// daripada di layar tempat tampilan disetel, dan halaman yang muat di sana
/// harus digulir di sini. Di layar seperti itu aplikasi digambar seolah
/// selebar [lebarAcuan], lalu dikecilkan pas ke layar. Ukuran layar, jarak
/// aman, dan keyboard di [MediaQuery] ikut dihitung ulang, jadi ketukan,
/// dialog, dan toast tetap pas. Ukuran font pilihan pemakai tetap berlaku.
class SkalaLayar extends StatelessWidget {
  final Widget child;

  const SkalaLayar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final skala = skalaUntukLebar(mq.size.width);
    if (skala >= 1) return child;
    final ukuran = mq.size / skala;
    return MediaQuery(
      data: mq.copyWith(
        size: ukuran,
        devicePixelRatio: mq.devicePixelRatio * skala,
        padding: mq.padding / skala,
        viewPadding: mq.viewPadding / skala,
        viewInsets: mq.viewInsets / skala,
        systemGestureInsets: mq.systemGestureInsets / skala,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: ukuran, child: child),
      ),
    );
  }
}
