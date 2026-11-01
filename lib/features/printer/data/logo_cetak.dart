import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'struk_cetak.dart' show titikKertas;

/// Lebar logo di nota: 140 titik ≈ 1,75 cm pada printer 203 dpi — 1 cm
/// terlalu kecil di kertas (tes owner 2026-11-01).
const lebarLogoTitik = 140;

/// Koreksi posisi logo dalam titik (negatif = ke kiri), untuk printer yang
/// kepala cetaknya tidak persis di tengah kertas. 0 = tengah hitungan.
const geserLogoTitik = 0;

const _asetLogo = 'assets/images/Logo Teras Inn.png';

List<int>? _simpanan;
var _sudahDiolah = false;

/// Perintah gambar ESC/POS logo Teras Inn, hitam-putih, di tengah kertas. Null kalau logonya gagal dibaca — nota
/// tetap dicetak tanpa logo. Hasilnya disimpan; logo hanya diolah sekali.
Future<List<int>?> logoEscPos() async {
  if (_sudahDiolah) return _simpanan;
  List<int>? hasil;
  try {
    final data = await rootBundle.load(_asetLogo);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final gambar = (await codec.getNextFrame()).image;
    final rgba = await gambar.toByteData(format: ui.ImageByteFormat.rawRgba);
    hasil = rasterLogo(
      rgba!.buffer.asUint8List(),
      gambar.width,
      gambar.height,
    );
    gambar.dispose();
  } catch (e) {
    debugPrint('[printer] logo gagal diolah: $e');
  }
  _sudahDiolah = true;
  return _simpanan = hasil;
}

/// Gambar RGBA [rgba] ([lebar]×[tinggi]) → perintah `GS v 0` (gambar
/// raster) dengan logo [lebarLogo] titik di tengah kertas selebar
/// [lebarKertas] titik, digeser [geser] titik (positif = ke kanan). Gambar
/// dimulai dari tepi kiri kertas dan berakhir di ujung kanan logo.
///
/// Aplikasi yang menengahkan, BUKAN printer: RPP02N mengabaikan lebar
/// gambar saat `ESC a 1` dan menaruh ujung kirinya di tengah kertas —
/// logo mulai dari tengah (tes owner 2026-11-01).
///
/// Bagian transparan dianggap putih (kertas), tepi kosong dipotong, lalu
/// diperkecil dengan merata-rata kotak sumber (garis tipis tidak hilang
/// begitu saja) dan dijadikan hitam-putih: lebih gelap dari [ambang] =
/// titik hitam.
@visibleForTesting
List<int> rasterLogo(
  Uint8List rgba,
  int lebar,
  int tinggi, {
  int lebarKertas = titikKertas,
  int lebarLogo = lebarLogoTitik,
  int geser = geserLogoTitik,
  int ambang = 160,
}) {
  // Kecerahan tiap piksel di atas kertas putih.
  final terang = Uint8List(lebar * tinggi);
  for (var i = 0; i < lebar * tinggi; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    final a = rgba[i * 4 + 3];
    final abu = (r * 299 + g * 587 + b * 114) ~/ 1000;
    terang[i] = 255 - ((255 - abu) * a ~/ 255);
  }

  // Potong tepi kosong.
  var x0 = lebar, y0 = tinggi, x1 = -1, y1 = -1;
  for (var y = 0; y < tinggi; y++) {
    for (var x = 0; x < lebar; x++) {
      if (terang[y * lebar + x] < 250) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return const [];
  final sw = x1 - x0 + 1, sh = y1 - y0 + 1;
  final w = lebarLogo < sw ? lebarLogo : sw;
  final h = (sh * w / sw).round().clamp(1, 1 << 16);

  // Tiap titik hasil = rata-rata kotak sumbernya.
  final kiri = ((lebarKertas - w) ~/ 2 + geser).clamp(0, lebarKertas - w);
  // Gambar berakhir di ujung kanan logo — sisa kertas di kanannya tidak
  // perlu dikirim. Data lebih sedikit = lebih kecil peluang byte hilang di
  // jalan (logo miring, tes owner 2026-11-01).
  final perBaris = (kiri + w + 7) ~/ 8;
  final bit = Uint8List(perBaris * h);
  for (var ty = 0; ty < h; ty++) {
    final sy0 = y0 + ty * sh ~/ h;
    final sy1 = (y0 + (ty + 1) * sh ~/ h).clamp(sy0 + 1, y1 + 1);
    for (var tx = 0; tx < w; tx++) {
      final sx0 = x0 + tx * sw ~/ w;
      final sx1 = (x0 + (tx + 1) * sw ~/ w).clamp(sx0 + 1, x1 + 1);
      var jumlah = 0, n = 0;
      for (var y = sy0; y < sy1; y++) {
        for (var x = sx0; x < sx1; x++) {
          jumlah += terang[y * lebar + x];
          n++;
        }
      }
      if (jumlah ~/ n < ambang) {
        final px = kiri + tx;
        bit[ty * perBaris + (px >> 3)] |= 0x80 >> (px & 7);
      }
    }
  }
  return [
    0x1D, 0x76, 0x30, 0x00, // GS v 0: gambar raster, ukuran normal
    perBaris & 0xFF, perBaris >> 8,
    h & 0xFF, h >> 8,
    ...bit,
  ];
}
