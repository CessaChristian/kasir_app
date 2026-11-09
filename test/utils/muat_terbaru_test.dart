import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/utils/muat_terbaru.dart';

/// Audit 6 Nov nomor 56: pemicu yang datang selagi memuat dirangkum.
void main() {
  test('pemicu beruntun selagi memuat → cukup satu muat ulang', () async {
    final pemicu = StreamController<void>();
    var dimuat = 0;
    final lambat = Completer<void>();
    final hasil = <int>[];
    final sub = muatTerbaru(pemicu.stream, () async {
      dimuat++;
      if (dimuat == 1) await lambat.future;
      return dimuat;
    }).listen(hasil.add);

    pemicu.add(null); // muat ke-1, tertahan
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20; i++) {
      pemicu.add(null);
    }
    await Future<void>.delayed(Duration.zero);
    lambat.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(dimuat, 2, reason: '20 pemicu selagi memuat = satu muat ulang');
    expect(hasil, [1, 2]);
    await sub.cancel();
  });

  test('pemicu sesudah selesai memuat tetap dimuat', () async {
    final pemicu = StreamController<void>();
    var dimuat = 0;
    final hasil = <int>[];
    final sub = muatTerbaru(
      pemicu.stream,
      () async => ++dimuat,
    ).listen(hasil.add);
    pemicu.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    pemicu.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(hasil, [1, 2]);
    await sub.cancel();
  });

  test('galat diteruskan, aliran tetap jalan', () async {
    final pemicu = StreamController<void>();
    var ke = 0;
    final hasil = <Object>[];
    final sub = muatTerbaru(pemicu.stream, () async {
      if (++ke == 1) throw StateError('gagal');
      return ke;
    }).listen(hasil.add, onError: hasil.add);
    pemicu.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    pemicu.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(hasil.first, isA<StateError>());
    expect(hasil.last, 2);
    await sub.cancel();
  });

  test('sumber selesai → aliran ditutup sesudah muat terakhir', () async {
    final pemicu = StreamController<void>();
    final hasil = await () {
      final f = muatTerbaru(pemicu.stream, () async => 'x').toList();
      pemicu
        ..add(null)
        ..close();
      return f;
    }();
    expect(hasil, ['x']);
  });
}
