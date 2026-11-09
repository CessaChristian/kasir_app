import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/shared/ui/header_teras.dart';

/// Temuan 9 Nov: tanggal di kanan header tidak berganti lewat tengah malam
/// selama halaman tetap terbuka.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('tanggal header berganti sendiri sesudah tengah malam', (
    t,
  ) async {
    final mulai = DateTime(2026, 11, 9, 23, 59, 30);
    var lewat = Duration.zero;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TanggalHeader(jam: () => mulai.add(lewat))),
      ),
    );
    expect(find.text('Senin'), findsOneWidget);
    expect(find.text('9 Nov 2026'), findsOneWidget);

    lewat = const Duration(seconds: 32);
    await t.pump(const Duration(seconds: 32));
    expect(find.text('Selasa'), findsOneWidget);
    expect(find.text('10 Nov 2026'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
  });
}
