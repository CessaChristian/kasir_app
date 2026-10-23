import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/penyimpanan_sesi_aman.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiket masuk Supabase pindah ke penyimpanan terenkripsi (revisi QA B7c),
/// TANPA membuat HP yang sudah terdaftar kehilangan sesinya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kunci = 'sb-proyek-auth-token';

  test('kunci sama dengan bawaan Supabase', () {
    expect(
      PenyimpananSesiAman.kunciUntuk('https://abcd1234.supabase.co'),
      'sb-abcd1234-auth-token',
    );
  });

  test('HP lama: tiket di SharedPreferences dipindah, yang lama dihapus',
      () async {
    SharedPreferences.setMockInitialValues({kunci: '{"tiket":"lama"}'});
    FlutterSecureStorage.setMockInitialValues({});
    final s = PenyimpananSesiAman(kunci: kunci);
    await s.initialize();

    expect(await s.hasAccessToken(), isTrue, reason: 'sesinya tidak hilang');
    expect(await s.accessToken(), '{"tiket":"lama"}');
    expect(await const FlutterSecureStorage().read(key: kunci),
        '{"tiket":"lama"}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kunci), isFalse,
        reason: 'tidak tertinggal sebagai teks biasa');
  });

  test('menyimpan & menghapus tiket memakai penyimpanan terenkripsi',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final s = PenyimpananSesiAman(kunci: kunci);
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);

    await s.persistSession('{"tiket":"baru"}');
    expect(await const FlutterSecureStorage().read(key: kunci),
        '{"tiket":"baru"}');
    expect((await SharedPreferences.getInstance()).containsKey(kunci), isFalse);

    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });

  test('sudah pernah pindah: tiket terenkripsi tidak ditimpa sisa lama',
      () async {
    SharedPreferences.setMockInitialValues({kunci: '{"tiket":"basi"}'});
    FlutterSecureStorage.setMockInitialValues({kunci: '{"tiket":"terbaru"}'});
    final s = PenyimpananSesiAman(kunci: kunci);
    await s.initialize();
    expect(await s.accessToken(), '{"tiket":"terbaru"}');
  });
}
