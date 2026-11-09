import 'dart:async';

/// Seperti `pemicu.asyncMap((_) => muat())`, tapi pemicu yang datang selagi
/// [muat] masih berjalan dirangkum jadi SATU muat ulang sesudahnya.
///
/// `asyncMap` mengantre setiap pemicu: sinkron yang menarik 20 halaman
/// membuat Laporan setahun dimuat ulang 20 kali berturut-turut, padahal
/// hanya hasil terakhir yang dipakai (audit 6 Nov nomor 56). Hasil akhirnya
/// tetap sama: sesudah pemicu terakhir selalu ada satu pemuatan yang dimulai
/// SESUDAH pemicu itu.
///
/// Galat dari [muat] diteruskan sebagai galat aliran, lalu aliran tetap
/// jalan — sama dengan `asyncMap`.
Stream<R> muatTerbaru<R>(Stream<void> pemicu, Future<R> Function() muat) {
  late StreamController<R> keluar;
  StreamSubscription<void>? langganan;
  var berjalan = false;
  var tertunda = false;
  var selesai = false;

  Future<void> jalan() async {
    berjalan = true;
    do {
      tertunda = false;
      try {
        final hasil = await muat();
        if (!keluar.isClosed) keluar.add(hasil);
      } catch (e, jejak) {
        if (!keluar.isClosed) keluar.addError(e, jejak);
      }
    } while (tertunda && !keluar.isClosed);
    berjalan = false;
    if (selesai && !keluar.isClosed) await keluar.close();
  }

  void mulai() {
    langganan = pemicu.listen(
      (_) {
        if (berjalan) {
          tertunda = true;
        } else {
          jalan();
        }
      },
      onError: (Object e, StackTrace jejak) => keluar.addError(e, jejak),
      onDone: () {
        selesai = true;
        if (!berjalan) keluar.close();
      },
    );
  }

  Future<void> berhenti() async {
    await langganan?.cancel();
    langganan = null;
  }

  keluar = pemicu.isBroadcast
      ? StreamController<R>.broadcast(onListen: mulai, onCancel: berhenti)
      : StreamController<R>(
          onListen: mulai,
          onPause: () => langganan?.pause(),
          onResume: () => langganan?.resume(),
          onCancel: berhenti,
        );
  return keluar.stream;
}
