import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/penjaga_izin.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Halaman berizin yang sedang terbuka ditutup begitu izinnya dicabut
/// (review C1/C2, keputusan owner 2026-11-04).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sm = SessionManager.instance;

  Future<void> masuk(List<String> izin) => sm.setSession(
    AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: null,
      permissions: izin,
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => sm.clearSession());

  Future<void> bukaLaporan(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PenjagaIzin(
                  izin: 'view_report',
                  namaFitur: 'Laporan',
                  child: Scaffold(body: Text('isi laporan')),
                ),
              ),
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    expect(find.text('isi laporan'), findsOneWidget);
  }

  testWidgets('izin dicabut selagi terbuka → halaman ditutup dengan pesan', (
    t,
  ) async {
    await t.runAsync(() => masuk(['view_report']));
    await bukaLaporan(t);

    await t.runAsync(() => masuk(const []));
    sm.sesiBerubah.value++;
    await t.pumpAndSettle();
    expect(find.text('isi laporan'), findsNothing);
    expect(find.text('Izin Laporan dicabut owner. Halaman ditutup.'),
        findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('perubahan sesi lain (izin tetap ada) → halaman tetap', (
    t,
  ) async {
    await t.runAsync(() => masuk(['view_report']));
    await bukaLaporan(t);
    await t.runAsync(() => masuk(['view_report', 'manage_products']));
    sm.sesiBerubah.value++;
    await t.pumpAndSettle();
    expect(find.text('isi laporan'), findsOneWidget);
  });
}
