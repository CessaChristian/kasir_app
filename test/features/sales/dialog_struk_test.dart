import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/sales/widgets/dialog_struk.dart';

/// Struk sesudah bayar yang gagal dimuat tidak boleh berputar selamanya:
/// kasir harus bisa menutupnya tanpa menutup paksa aplikasi.
class _RepoGagal extends SalesRepository {
  _RepoGagal(super.db, {required this.lempar});

  final bool lempar;
  var dipanggil = 0;

  @override
  Future<Transaction?> ambilTransaksi(String id) async {
    dipanggil++;
    if (lempar) throw StateError('database rusak');
    return null;
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> buka(WidgetTester t, SalesRepository repo) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => tampilkanStrukSesudahBayar(
                c,
                transaksiId: 'tidak-ada',
                repo: repo,
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

  for (final lempar in [false, true]) {
    testWidgets(
      lempar
          ? 'galat saat memuat: pesan + Tutup, bukan berputar'
          : 'transaksi tidak ditemukan: pesan + Tutup, bukan berputar',
      (t) async {
        final repo = _RepoGagal(db, lempar: lempar);
        await buka(t, repo);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Struk tidak bisa dimuat.'), findsOneWidget);

        await t.tap(find.text('Coba lagi'));
        await t.pumpAndSettle();
        expect(repo.dipanggil, 2);

        await t.tap(find.text('Tutup'));
        await t.pumpAndSettle();
        expect(find.text('Struk tidak bisa dimuat.'), findsNothing);
      },
    );
  }
}
