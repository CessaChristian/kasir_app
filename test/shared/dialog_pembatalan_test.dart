import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/tombol_lembar.dart';
import 'package:kasir_app/shared/widgets/dialog_pembatalan.dart';

/// Dialog pembatalan (desain): alasan → berhasil. PIN owner tidak diminta
/// lagi (keputusan owner 2026-10-24) — kasir maupun owner cukup memilih
/// alasan.
void main() {
  Future<bool? Function()> buka(
    WidgetTester t, {
    required Future<void> Function(String) kirim,
  }) async {
    // Ukuran layar HP sungguhan (1080x2400 @3x), bukan bawaan 800x600.
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    bool? hasil;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            hasil = await tampilkanDialogPembatalan(
              context,
              pertanyaan: 'Kenapa pengeluaran Es Batu dibatalkan?',
              judulBerhasil: 'Pengeluaran berhasil dibatalkan',
              keteranganBerhasil: 'Tidak dihitung.',
              daftarAlasan: const ['Salah input nominal', alasanLainnya],
              kirim: kirim,
            );
          },
          child: const Text('buka'),
        ),
      ),
    ));
    return () => hasil;
  }

  Future<void> tekanTombol(WidgetTester t, String label) async {
    final tombol = find.widgetWithText(FilledButton, label);
    await t.ensureVisible(tombol);
    await t.tap(tombol);
    await t.pumpAndSettle();
  }

  testWidgets('pilih alasan lalu Batalkan: langsung berhasil, tanpa PIN', (
    t,
  ) async {
    final dikirim = <String>[];
    final hasil = await buka(t, kirim: (a) async => dikirim.add(a));
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Batalkan'))
        .onPressed, isNull, reason: 'belum memilih alasan');
    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    await tekanTombol(t, 'Batalkan');

    expect(dikirim, ['Salah input nominal']);
    expect(find.text('Masukkan PIN'), findsNothing);
    expect(find.text('Pengeluaran berhasil dibatalkan'), findsOneWidget);
    await tekanTombol(t, 'Selesai');
    expect(hasil(), isTrue);
  });

  testWidgets('ditolak (mis. sudah dibatalkan HP lain): pesannya tampil, '
      'dialog tetap di langkah alasan', (t) async {
    await buka(t, kirim: (a) async {
      throw StateError('Pengeluaran ini sudah dibatalkan.');
    });
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    await tekanTombol(t, 'Batalkan');
    expect(find.text('Pengeluaran ini sudah dibatalkan.'), findsOneWidget);
    expect(find.text('Alasan pembatalan'), findsOneWidget);
  });

  testWidgets('QA K6: galat tak terduga — tidak macet "Memproses…", bisa '
      'dicoba lagi', (t) async {
    var coba = 0;
    await buka(t, kirim: (a) async {
      coba++;
      throw Exception('database is locked');
    });
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    await tekanTombol(t, 'Batalkan');
    expect(find.text('Memproses…'), findsNothing);
    expect(find.text('Gagal membatalkan. Coba lagi.'), findsOneWidget);
    await tekanTombol(t, 'Batalkan');
    expect(coba, 2);
  });

  testWidgets('"Lainnya" wajib diisi dan disimpan dengan awalan', (t) async {
    String? alasan;
    await buka(t, kirim: (a) async => alasan = a);
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    await t.tap(find.text(alasanLainnya));
    await t.pumpAndSettle(); // kotak teks muncul, dialog membesar
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Batalkan'))
        .onPressed, isNull);
    await t.enterText(find.byType(TextField), 'Dobel dicatat');
    await t.pumpAndSettle();
    await tekanTombol(t, 'Batalkan');
    expect(alasan, 'Lainnya: Dobel dicatat');
  });

  testWidgets('tombol Batalkan nonaktif sampai alasan dipilih', (t) async {
    var dikirim = false;
    await buka(t, kirim: (_) async => dikirim = true);
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    TombolLembar batalkan() => t.widget<TombolLembar>(
      find.widgetWithText(TombolLembar, 'Batalkan'),
    );
    expect(batalkan().onPressed, isNull, reason: 'belum ada alasan');
    expect(batalkan().sudut, 12, reason: 'ukuran desain dialog ini');
    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    expect(batalkan().onPressed, isNotNull);
    expect(dikirim, isFalse);
  });

  testWidgets('Batal menutup dialog tanpa membatalkan apa pun', (t) async {
    var dipanggil = false;
    final hasil = await buka(t, kirim: (a) async => dipanggil = true);
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    await tekanTombol(t, 'Batal');
    expect(dipanggil, isFalse);
    expect(hasil(), isFalse);
  });
}
