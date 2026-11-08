import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/features/shift/models/format_shift.dart';

/// Audit 6 Nov nomor 49: shift yang lupa ditutup berhari-hari.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  final senin = DateTime(2026, 11, 2, 8);

  test('lama shift: di bawah sehari tetap "2j 15m"', () {
    expect(lamaShift(senin, DateTime(2026, 11, 2, 10, 15)), '2j 15m');
    expect(lamaShift(senin, DateTime(2026, 11, 2, 8, 40)), '40m');
  });

  test('lama shift: sehari atau lebih ditulis hari dan jam', () {
    expect(lamaShift(senin, DateTime(2026, 11, 10, 9, 7)), '8 hari 1 jam');
    expect(lamaShift(senin, DateTime(2026, 11, 3, 8, 30)), '1 hari');
  });

  test('jam mulai: hari ini cuma jam, hari lain dengan tanggal', () {
    expect(jamMulaiShift(senin, DateTime(2026, 11, 2, 15)), '08:00');
    expect(jamMulaiShift(senin, DateTime(2026, 11, 5, 15)), 'Sen 2 Nov 08:00');
  });
}
