import 'package:flutter/material.dart';

import 'teks_teras.dart';
import 'warna_teras.dart';

/// Jalankan [kerja] sambil menampilkan kartu "[pesan]" yang mengunci layar.
///
/// Untuk tombol yang harus bertanya ke server sebelum bisa menampilkan
/// apa pun (mis. "Tutup shift"): tanpa tanda, kasir mengira ketukannya tidak
/// masuk dan mengetuk lagi — dan setiap ketukan menjalankan prosesnya dari
/// awal. Kartunya muncul seketika dan menghalangi ketukan berikutnya sampai
/// [kerja] selesai; tombol Kembali juga ditahan.
Future<T> jalankanDenganMemuat<T>(
  BuildContext context,
  Future<T> Function() kerja, {
  required String pesan,
}) async {
  final navigator = Navigator.of(context);
  final kartu = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: _KartuMemuat(pesan)),
  );
  navigator.push(kartu);
  try {
    return await kerja();
  } finally {
    // removeRoute, bukan pop: yang paling atas belum tentu kartunya, dan
    // pemanggilnya bisa sudah tidak terpasang lagi.
    if (kartu.isActive) navigator.removeRoute(kartu);
  }
}

class _KartuMemuat extends StatelessWidget {
  final String pesan;

  const _KartuMemuat(this.pesan);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: WarnaTeras.kartu,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: WarnaTeras.oranye,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                pesan,
                style: const TextStyle(
                  fontSize: TeksTeras.biasa,
                  fontWeight: FontWeight.w600,
                  color: WarnaTeras.teks,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
