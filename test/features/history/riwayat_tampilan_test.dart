import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/history/history_page.dart';
import 'package:kasir_app/shared/auth/cakupan_riwayat.dart';

/// Tampilan halaman Riwayat.
///
/// - Judul tanggal selalu "Hari, dd/MM/yyyy" untuk semua akun — tidak ada lagi
///   "Hari Ini" / "Kemarin".
/// - Kasir tanpa izin Lihat Riwayat Lengkap tidak punya saringan periode:
///   semua transaksi shift berjalan selalu tampil, termasuk yang jatuh di
///   bulan sebelumnya.
void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  Transaction trx(String id, DateTime saat) => Transaction(
        id: id,
        invoiceNo: '',
        createdAt: saat,
        total: 10000,
        paymentMethod: 'cash',
        orderType: 'dine_in',
        updatedAt: saat,
        syncStatus: 'synced',
      );

  test('judul tanggal "Jumat, 02/10/2026" — juga untuk hari ini', () {
    expect(labelTanggalRiwayat(DateTime(2026, 10, 2, 18, 10)),
        'Jumat, 02/10/2026');
    final sekarang = DateTime.now();
    expect(labelTanggalRiwayat(sekarang), isNot(anyOf('Hari Ini', 'Kemarin')));
  });

  // Shift dimulai 30 September dan masih berjalan 2 Oktober.
  final semua = [
    trx('30-sep', DateTime(2026, 9, 30, 15, 30)),
    trx('02-okt', DateTime(2026, 10, 2, 18, 10)),
  ];
  final oktober = DateTime(2026, 10);

  test('kasir tanpa izin melihat SELURUH shift, walau beda bulan', () {
    final hasil = saringPeriodeRiwayat(semua,
        cakupan: JenisCakupan.shiftAktif, bulan: oktober);
    expect(hasil.map((t) => t.id), ['30-sep', '02-okt'],
        reason: 'saringan "Bulan Ini" dulu menyembunyikan transaksi tanggal '
            '30 padahal masih satu shift');
  });

  test('yang boleh melihat ke belakang tetap bisa menyaring per bulan', () {
    for (final cakupan in [JenisCakupan.semua, JenisCakupan.milikSendiri]) {
      final hasil =
          saringPeriodeRiwayat(semua, cakupan: cakupan, bulan: oktober);
      expect(hasil.map((t) => t.id), ['02-okt']);
      expect(
          saringPeriodeRiwayat(semua, cakupan: cakupan, bulan: null),
          hasLength(2),
          reason: 'Semua Waktu');
    }
  });
}
