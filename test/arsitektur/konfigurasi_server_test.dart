import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/supabase/supabase_config.dart';

/// Mengunci agar APK tidak bisa lagi diam-diam lahir tanpa server.
///
/// ── BUG YANG DIKUNCI ──
///
/// `url` dan `anonKey` dulu diambil dari `--dart-define`. Kalau flag-nya lupa
/// ditulis saat build, keduanya jadi string kosong, `tersedia` jadi false, dan
/// aplikasi berubah menjadi aplikasi offline murni: `SupabaseService.init()`
/// langsung menyerah, dan pemeriksaan "tanya server dulu sebelum menawarkan
/// Setup Akun Owner" dilewati sepenuhnya.
///
/// Aplikasinya tetap berjalan mulus dan tidak mengeluh sedikit pun. Sudah
/// terjadi: APK release tanpa flag langsung menampilkan "Setup Akun Owner"
/// seolah server tidak ada.
///
/// Test ini berjalan TANPA `--dart-define` apa pun — persis keadaan yang dulu
/// menghasilkan bug itu.
void main() {
  test('server tetap terkonfigurasi walau dibangun tanpa --dart-define', () {
    expect(SupabaseConfig.url, isNotEmpty);
    expect(SupabaseConfig.anonKey, isNotEmpty);
    expect(
      SupabaseConfig.tersedia,
      isTrue,
      reason: 'Kalau ini false, APK yang dibangun tanpa flag akan diam-diam '
          'berubah jadi aplikasi offline murni — tanpa satu pun tanda di '
          'layar, dan baru ketahuan setelah berhari-hari data menumpuk di '
          'satu HP saja.',
    );
  });

  test('url menunjuk Supabase lewat https', () {
    expect(SupabaseConfig.url, startsWith('https://'));
    expect(SupabaseConfig.url, contains('.supabase.co'));
  });

  test('anonKey berbentuk JWT, bukan kunci lain yang tersalin', () {
    // Menempelkan `service_role` di sini akan memberi seluruh dunia akses
    // penuh ke database, menembus RLS. Bentuknya mirip — sama-sama JWT
    // panjang — jadi mudah tertukar saat menyalin dari dashboard.
    expect(SupabaseConfig.anonKey, startsWith('eyJ'));
    expect(SupabaseConfig.anonKey.split('.'), hasLength(3));
  });

  test('service_role TIDAK BOLEH ada di mana pun dalam kode', () {
    final pelanggar = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('service_role')) {
        pelanggar.add(entity.path);
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'Kunci service_role menembus RLS sepenuhnya. Ia tidak pernah '
            'boleh menyentuh aplikasi, apalagi repositori publik.');
  });

  test('kredensial perangkat TIDAK ditempel di kode', () {
    // Ini satu-satunya rahasia sungguhan di antara keempat nilai, dan
    // repositorinya publik. Menempelnya mengubah taruhan dari "harus punya
    // APK dan tahu cara membongkarnya" menjadi "cukup buka GitHub".
    final isi = File('lib/data/supabase/supabase_config.dart').readAsStringSync();
    expect(isi, contains("String.fromEnvironment('SUPABASE_DEVICE_EMAIL')"));
    expect(isi, contains("String.fromEnvironment('SUPABASE_DEVICE_PASSWORD')"));
    expect(SupabaseConfig.adaKredensialPerangkat, isFalse,
        reason: 'test berjalan tanpa --dart-define, jadi ini harus kosong — '
            'kalau true, berarti kredensialnya tertulis di dalam kode');
  });
}
