import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/perangkat/kode_nota.dart';

/// Penanda HP di nomor nota: huruf pembagian server (A, B, C, ...), atau
/// kode acak lama selama huruf itu belum diketahui.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(KodeNota.resetUntukTest);

  test('belum tahu huruf dari server: kode acak lama', () async {
    FlutterSecureStorage.setMockInitialValues({'kode_nota_perangkat': 'K7QX'});
    expect(await KodeNota.untukNota(), 'K7QX');
  });

  test('sudah tahu huruf dari server: huruf itu yang dipakai', () async {
    FlutterSecureStorage.setMockInitialValues({'kode_nota_perangkat': 'K7QX'});
    await KodeNota.simpanDariServer('B');
    expect(await KodeNota.untukNota(), 'B');
    // Identitas baru → huruf baru menimpa yang lama.
    await KodeNota.simpanDariServer('D');
    expect(await KodeNota.untukNota(), 'D');
  });

  test(
    'huruf tersimpan di brankas terbaca setelah aplikasi dibuka ulang',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'kode_nota_perangkat': 'K7QX',
        'kode_perangkat_server': 'C',
      });
      expect(await KodeNota.untukNota(), 'C');
    },
  );
}
