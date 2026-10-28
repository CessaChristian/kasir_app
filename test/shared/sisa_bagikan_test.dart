import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/services/simpan_berkas.dart';

/// Berkas laporan yang dibagikan dulu tidak pernah dihapus dari folder
/// sementara (revisi QA, temuan K4).
void main() {
  test('sisa bagikan lebih dari sehari dibuang, yang baru dibiarkan', () async {
    final folder = Directory.systemTemp.createTempSync('uji_bagikan');
    addTearDown(() => folder.deleteSync(recursive: true));
    final sekarang = DateTime(2026, 10, 28, 12);

    final lama = File('${folder.path}/Laporan_lama.pdf')
      ..writeAsStringSync('x');
    lama.setLastModifiedSync(sekarang.subtract(const Duration(days: 2)));
    final baru = File('${folder.path}/Laporan_baru.pdf')
      ..writeAsStringSync('x');
    baru.setLastModifiedSync(sekarang.subtract(const Duration(hours: 3)));

    await buangSisaBagikan(folder, sekarang: sekarang);
    expect(lama.existsSync(), isFalse);
    expect(baru.existsSync(), isTrue, reason: 'mungkin masih dibaca Gmail');
  });

  test('folder belum ada: tidak melempar galat', () async {
    await buangSisaBagikan(
      Directory('${Directory.systemTemp.path}/tidak_ada_x'),
    );
  });
}
