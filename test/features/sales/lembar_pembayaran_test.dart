import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/features/sales/models/pesanan.dart';
import 'package:kasir_app/features/sales/sheets/lembar_pembayaran.dart';

/// Lembar pembayaran tidak boleh tertutup selama transaksinya disimpan —
/// lewat tombol Back, ketuk di luar, maupun digeser ke bawah.
void main() {
  bool? hasil;

  Future<void> pasang(
    WidgetTester t,
    Future<void> Function(int) bayar, {
    MetodeBayar metode = MetodeBayar.qris,
  }) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    hasil = null;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => hasil = await tampilkanPembayaran(
                c,
                total: 18000,
                metode: metode,
                bayar: bayar,
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
  }

  Future<void> geserTutup(WidgetTester t) async {
    await t.drag(find.text('Pembayaran QRIS'), const Offset(0, 600));
    await t.pumpAndSettle();
  }

  testWidgets('audit nomor 33: sesudah tombol nominal, ketikan masuk di '
      'belakang angka', (t) async {
    await pasang(t, (_) async {}, metode: MetodeBayar.tunai);
    await t.tap(find.text('Rp 20.000').last);
    await t.pump();
    final kolom = t.widget<TextField>(find.byType(TextField)).controller!;
    expect(kolom.selection, TextSelection.collapsed(offset: kolom.text.length),
        reason: 'kursor harus di akhir, bukan -1');
  });

  testWidgets('belum memproses: lembar bisa digeser tutup', (t) async {
    await pasang(t, (_) async {});
    await geserTutup(t);
    expect(find.text('Pembayaran QRIS'), findsNothing);
    expect(hasil, isFalse);
  });

  testWidgets('sedang memproses: digeser ke bawah tetap terbuka', (t) async {
    final simpan = Completer<void>();
    await pasang(t, (_) => simpan.future);
    await t.tap(find.text('Sudah Bayar'));
    await t.pump();
    expect(find.text('Memproses…'), findsOneWidget);

    await geserTutup(t);
    expect(find.text('Pembayaran QRIS'), findsOneWidget,
        reason: 'lembar tertutup di tengah penyimpanan');

    // Ketuk di luar lembar dan tombol Back juga tidak menutupnya.
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Pembayaran QRIS'), findsOneWidget);

    simpan.complete();
    await t.pumpAndSettle();
    expect(find.text('Pembayaran QRIS'), findsNothing);
    expect(hasil, isTrue, reason: 'selesai disimpan: lembar tertutup sendiri');
  });

  testWidgets('penyimpanan gagal: lembar bisa digeser lagi', (t) async {
    await pasang(t, (_) async => throw StateError('Gagal simpan'));
    await t.tap(find.text('Sudah Bayar'));
    await t.pumpAndSettle();
    expect(find.text('Sudah Bayar'), findsOneWidget);
    await geserTutup(t);
    expect(find.text('Pembayaran QRIS'), findsNothing);
    await t.pump(const Duration(seconds: 5)); // toast galat menghilang
  });
}
