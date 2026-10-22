import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/widgets/pencatat_sentuhan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sentuhan di mana pun — termasuk di dalam lembar bawah — dicatat sebagai
/// kabar, dan tetap sampai ke tombol yang disentuh.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sentuhan di lembar bawah tercatat dan tombolnya tetap jalan', (
    t,
  ) async {
    var ditekan = 0;
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => PencatatSentuhan(child: child!),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: c,
              builder: (_) => TextButton(
                onPressed: () => ditekan++,
                child: const Text('Tambah'),
              ),
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    final sebelum = SessionManager.instance.sentuhanTerakhir;
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.tap(find.text('Tambah'));
    await t.pump();

    expect(ditekan, 1, reason: 'sentuhannya diteruskan');
    final sesudah = SessionManager.instance.sentuhanTerakhir;
    expect(sesudah, isNotNull);
    expect(sebelum == null || sesudah!.isAfter(sebelum), isTrue,
        reason: 'sentuhan di dalam lembar ikut tercatat');
  });

  test('terpasang di akar aplikasi, dan laporan aktif ikut detak tiap menit',
      () {
    // Tanpa dua sambungan ini, perilaku di atas tidak pernah jalan di HP.
    expect(File('lib/main.dart').readAsStringSync(),
        contains('PencatatSentuhan(child: SkalaLayar(child: child!))'));
    final otomatis =
        File('lib/data/sync/sync_otomatis.dart').readAsStringSync();
    expect(otomatis, contains('await laporAktifKalauPerlu();'));
  });
}
