import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/sync/kemajuan_sync.dart';
import 'package:kasir_app/data/sync/sync_service.dart';
import 'package:kasir_app/shared/widgets/dialog_sync.dart';

/// Mengunci isi popup kemajuan sinkronisasi.
///
/// ── KENAPA SESEDERHANA INI ──
///
/// Popup ini dulu menampilkan nama tabel, jumlah baris, dan nomor tahap:
/// "Mengambil Transaksi · 0/0 diperiksa · Tahap 6/9". Tidak satu pun berarti
/// bagi pemilik warung — ia bahkan tidak tahu aplikasinya punya sembilan
/// tahap, dan "0/0 diperiksa" justru membingungkan.
///
/// Yang benar-benar ingin diketahui pengguna cuma satu: masih jalan, dan
/// sejauh mana.
void main() {
  Future<void> pasang(WidgetTester tester, KemajuanSync? k) async {
    SyncService.instance.kemajuan.value = k;
    await tester.pumpWidget(const MaterialApp(home: DialogSync()));
    await tester.pump();
  }

  tearDown(() => SyncService.instance.kemajuan.value = null);

  testWidgets('sebelum laporan pertama: menyambung', (tester) async {
    await pasang(tester, null);

    expect(find.text('Menyambung…'), findsOneWidget);
    expect(find.text('Menghubungi server'), findsOneWidget);
  });

  testWidgets('sedang berjalan: judul + PERSENTASE saja', (tester) async {
    // Tahap 5 dari 9, setengah jalan di tabelnya -> (4 + 0.5) / 9 = 50%
    await pasang(
      tester,
      const KemajuanSync(
        tahap: 'menarik',
        entitas: 'transactions',
        entitasKe: 5,
        totalEntitas: 9,
        baris: 50,
        totalBaris: 100,
        perubahan: 12,
      ),
    );

    expect(find.text('Menyinkronkan Data'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('TIDAK menampilkan rincian yang tidak berarti bagi pengguna',
      (tester) async {
    await pasang(
      tester,
      const KemajuanSync(
        tahap: 'menarik',
        entitas: 'transactions',
        entitasKe: 6,
        totalEntitas: 9,
        baris: 0,
        totalBaris: 0,
        perubahan: 0,
      ),
    );

    for (final dilarang in const [
      'Transaksi',        // nama tabel
      'Tahap 6/9',        // nomor tahap
      '0/0 diperiksa',    // hitungan baris
      'Mengambil',        // arah sinkron
    ]) {
      expect(find.textContaining(dilarang), findsNothing,
          reason: '"$dilarang" tidak berarti apa-apa bagi pemilik warung');
    }
  });

  testWidgets('persentase dibulatkan, tidak pernah melebihi 100',
      (tester) async {
    await pasang(
      tester,
      const KemajuanSync(
        tahap: 'gambar',
        entitas: 'gambar',
        entitasKe: 9,
        totalEntitas: 9,
        baris: 10,
        totalBaris: 10,
      ),
    );

    expect(find.text('100%'), findsOneWidget);
  });
}
