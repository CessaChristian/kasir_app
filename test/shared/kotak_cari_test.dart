import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/shared/ui/kotak_cari.dart';

/// Review E1: pencarian Riwayat dulu menyaring ulang seluruh transaksi
/// periode di setiap huruf.
void main() {
  testWidgets('dengan jeda: dikabarkan sekali, sesudah berhenti mengetik',
      (t) async {
    final dikabari = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KotakCari(
          nilai: '',
          jeda: const Duration(milliseconds: 300),
          onBerubah: dikabari.add,
        ),
      ),
    ));
    for (final teks in ['n', 'na', 'nas', 'nasi']) {
      await t.enterText(find.byType(TextField), teks);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(dikabari, isEmpty, reason: 'masih mengetik');
    await t.pump(const Duration(milliseconds: 300));
    expect(dikabari, ['nasi']);

    // Tombol hapus tetap langsung.
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump();
    expect(dikabari.last, '');
  });

  testWidgets(
      'audit nomor 37: digulir keluar layar lalu kembali, kata cari tetap '
      'terlihat', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: _Halaman())));
    await t.enterText(find.byType(TextField), 'kopi');
    await t.pump();
    // Kasir menutup keyboard dulu, lalu menggulir.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await t.drag(find.byType(ListView), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(find.byType(KotakCari), findsNothing, reason: 'sudah tergulir');
    await t.drag(find.byType(ListView), const Offset(0, 3000));
    await t.pumpAndSettle();
    expect(find.text('kopi'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });
}

/// Seperti halaman Kasir: kotak cari di dalam daftar yang digulir, kata
/// carinya disimpan halaman.
class _Halaman extends StatefulWidget {
  const _Halaman();
  @override
  State<_Halaman> createState() => _HalamanState();
}

class _HalamanState extends State<_Halaman> {
  var _kata = '';
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          KotakCari(nilai: _kata, onBerubah: (v) => setState(() => _kata = v)),
          for (var i = 0; i < 60; i++)
            SizedBox(height: 80, child: Text('baris $i $_kata')),
        ],
      );
}
