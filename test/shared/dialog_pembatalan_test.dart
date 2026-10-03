import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/widgets/dialog_pembatalan.dart';

/// Dialog pembatalan (desain): alasan → (kasir) PIN → berhasil.
void main() {
  Future<bool? Function()> buka(
    WidgetTester t, {
    required bool perluPin,
    required Future<void> Function(String, String?) kirim,
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
              keteranganPin: 'Masukkan PIN.',
              judulBerhasil: 'Pengeluaran berhasil dibatalkan',
              keteranganBerhasil: 'Tidak dihitung.',
              daftarAlasan: const ['Salah input nominal', alasanLainnya],
              perluPin: perluPin,
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

  testWidgets('owner: tanpa PIN, langsung berhasil', (t) async {
    final dikirim = <(String, String?)>[];
    final hasil = await buka(t, perluPin: false, kirim: (a, p) async {
      dikirim.add((a, p));
    });
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Batalkan'))
        .onPressed, isNull, reason: 'belum memilih alasan');
    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    await tekanTombol(t, 'Batalkan');

    expect(dikirim, [('Salah input nominal', null)]);
    expect(find.text('Pengeluaran berhasil dibatalkan'), findsOneWidget);
    await tekanTombol(t, 'Selesai');
    expect(hasil(), isTrue);
  });

  testWidgets('kasir: PIN salah tetap di langkah PIN, PIN benar berhasil',
      (t) async {
    final pinDicoba = <String?>[];
    final hasil = await buka(t, perluPin: true, kirim: (a, p) async {
      pinDicoba.add(p);
      if (p != '135790') throw StateError('PIN salah.');
    });
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();

    await t.tap(find.text('Salah input nominal'));
    await t.pump();
    await tekanTombol(t, 'Lanjut');
    expect(find.text('Masukkan PIN'), findsOneWidget);

    final isian = find.byKey(const Key('isian-pin-pembatalan'));
    await t.enterText(isian, '111111');
    await t.pumpAndSettle();
    expect(find.text('PIN salah.'), findsOneWidget);
    expect(find.text('Masukkan PIN'), findsOneWidget);

    await t.enterText(isian, '135790');
    await t.pumpAndSettle();
    expect(pinDicoba, ['111111', '135790']);
    expect(find.text('Pengeluaran berhasil dibatalkan'), findsOneWidget);
    await tekanTombol(t, 'Selesai');
    expect(hasil(), isTrue);
  });

  testWidgets('"Lainnya" wajib diisi dan disimpan dengan awalan', (t) async {
    String? alasan;
    await buka(t, perluPin: false, kirim: (a, p) async => alasan = a);
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

  testWidgets('Batal menutup dialog tanpa membatalkan apa pun', (t) async {
    var dipanggil = false;
    final hasil = await buka(t, perluPin: false, kirim: (a, p) async {
      dipanggil = true;
    });
    await t.pump();
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
    await tekanTombol(t, 'Batal');
    expect(dipanggil, isFalse);
    expect(hasil(), isFalse);
  });
}
