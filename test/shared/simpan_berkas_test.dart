import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/services/simpan_berkas.dart';

/// Pesan gagal simpan laporan harus bisa dibaca owner, bukan pesan Android
/// mentah (audit nomor 4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kanal = MethodChannel('kasir_app/unduhan');

  Future<String> gagalDengan(String kode, String? pesan) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, (_) async {
          throw PlatformException(code: kode, message: pesan);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, null),
    );
    try {
      await SimpanBerkas.keDownload(
        nama: 'a.pdf',
        mime: 'application/pdf',
        bita: Uint8List(1),
      );
    } on BerkasTidakTersimpan catch (e) {
      return e.pesan;
    }
    fail('seharusnya gagal');
  }

  test('memori penuh: disuruh mengosongkan memori', () async {
    final pesan = await gagalDengan(
      'GAGAL',
      'write failed: ENOSPC (No space left on device)',
    );
    expect(pesan, contains('Memori HP penuh'));
    expect(pesan, isNot(contains('ENOSPC')));
  });

  test('galat lain: tanpa pesan mentah, ada saran Bagikan', () async {
    final pesan = await gagalDengan('GAGAL', 'java.io.IOException: boom');
    expect(pesan, isNot(contains('IOException')));
    expect(pesan, contains('Bagikan'));
  });
}
