import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/expenses/models/kategori_biaya.dart';
import 'package:kasir_app/features/expenses/models/ringkasan_pengeluaran.dart';

/// Isi halaman Pengeluaran owner: total, kategori, rincian per hari.
void main() {
  var n = 0;
  Expense e(int jumlah, DateTime waktu,
          {String kategori = 'bahan_baku', bool batal = false}) =>
      Expense(
        id: 'e${n++}',
        shiftId: 's',
        userId: 'budi',
        description: 'x',
        amount: jumlah,
        category: kategori,
        qty: 1,
        createdAt: waktu,
        updatedAt: waktu,
        deletedAt: batal ? waktu : null,
        syncStatus: 'synced',
      );

  test('yang dibatalkan tidak dihitung, tapi tetap muncul di harinya', () {
    final r = ringkasPengeluaran([
      e(10000, DateTime(2026, 10, 1, 9), kategori: 'bahan_baku'),
      e(99000, DateTime(2026, 10, 1, 10), kategori: 'asset', batal: true),
      e(5000, DateTime(2026, 10, 2, 8), kategori: 'operasional_kedai'),
    ]);
    expect(r.total, 15000);
    expect(r.jumlahItem, 2);
    expect(r.jumlahHari, 2);
    expect(r.perKategori.map((k) => k.$1), isNot(contains('Asset')),
        reason: 'kategori yang isinya cuma pembatalan tidak tampil');
    final satuOkt = r.perHari.firstWhere((h) => h.tanggal.day == 1);
    expect(satuOkt.isi, hasLength(2));
    expect(satuOkt.total, 10000);
  });

  test('kategori dijumlahkan, diurutkan terbesar dulu', () {
    final r = ringkasPengeluaran([
      e(10000, DateTime(2026, 10, 1, 9), kategori: 'bahan_baku'),
      e(30000, DateTime(2026, 10, 1, 9), kategori: 'operasional_kedai'),
      e(15000, DateTime(2026, 10, 1, 9), kategori: 'bahan_baku'),
      e(2000, DateTime(2026, 10, 1, 9), kategori: 'asset'),
    ]);
    expect(r.perKategori, [
      ('Operasional Kedai', 30000),
      ('Bahan Baku', 25000),
      ('Asset', 2000),
    ]);
  });

  test('hari terbaru dulu, isi hari terbaru dulu', () {
    final r = ringkasPengeluaran([
      e(1, DateTime(2026, 10, 1, 9)),
      e(2, DateTime(2026, 10, 3, 8)),
      e(3, DateTime(2026, 10, 3, 18)),
    ]);
    expect(r.perHari.map((h) => h.tanggal.day), [3, 1]);
    expect(r.perHari.first.isi.map((x) => x.amount), [3, 2]);
  });

  test('periode tanpa pengeluaran: kosong, total nol', () {
    final r = ringkasPengeluaran(const []);
    expect(r.kosong, isTrue);
    expect(r.total, 0);
    expect(r.perKategori, isEmpty);
  });

  test('label kategori dari kode', () {
    expect(KategoriBiaya.labelDari('bahan_baku'), 'Bahan Baku');
    expect(KategoriBiaya.labelDari('operasional_kedai'), 'Operasional Kedai');
    expect(KategoriBiaya.values.map((k) => k.label),
        ['Asset', 'Bahan Baku', 'Operasional Kedai'],
        reason: 'hanya tiga, tanpa "Lainnya"');
  });
}
