import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/permission_repository.dart';
import 'package:kasir_app/features/dashboard/pages/dasbor_kasir_page.dart';
import 'package:kasir_app/features/expenses/expenses_page.dart';
import 'package:kasir_app/features/expenses/pages/pengeluaran_owner_page.dart';
import 'package:kasir_app/features/expenses/repositories/expense_repository.dart';
import 'package:kasir_app/features/history/models/saringan_riwayat.dart';
import 'package:kasir_app/features/history/widgets/daftar_riwayat.dart';
import 'package:kasir_app/features/open_bill/repositories/open_bill_repository.dart';
import 'package:kasir_app/features/open_bill/sheets/lembar_open_bill.dart';
import 'package:kasir_app/features/owner/pages/hak_akses_page.dart';
import 'package:kasir_app/features/owner/pages/kelola_kasir_page.dart';
import 'package:kasir_app/features/owner/repositories/cashier_repository.dart';
import 'package:kasir_app/features/owner/models/ringkasan_kasir.dart';
import 'package:kasir_app/features/products/pages/kategori_page.dart';
import 'package:kasir_app/features/products/pages/products_page.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/products/sheets/product_form_sheet.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/sales/sales_page.dart';
import 'package:kasir_app/features/shift/models/ringkasan_shift.dart';
import 'package:kasir_app/features/shift/pages/detail_shift_page.dart';
import 'package:kasir_app/features/shift/pages/riwayat_shift_page.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/cakupan_riwayat.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/services/catatan_error.dart';
import 'package:kasir_app/shared/ui/galat_muat.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
import 'package:kasir_app/shared/widgets/transaction_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data gagal dimuat: tampil pesan dan tombol Coba lagi, bukan lingkaran yang
/// berputar selamanya atau "Shift tidak ditemukan" (audit nomor 6).
final _galat = Exception('database rusak');

class _ProdukGagal extends ProductRepository {
  _ProdukGagal(super.db);
  var gagal = true;

  @override
  Stream<List<Product>> watchProducts() =>
      gagal ? Stream.error(_galat) : super.watchProducts();
}

/// Hanya kategori yang gagal; produk tetap termuat.
class _KategoriGagal extends ProductRepository {
  _KategoriGagal(super.db);
  var gagal = true;

  @override
  Stream<List<Category>> watchCategories() =>
      gagal ? Stream.error(_galat) : super.watchCategories();
}

class _ShiftGagal extends ShiftRepository {
  _ShiftGagal(super.db);
  var gagal = true;

  @override
  Stream<RingkasanShift?> watchShift(String shiftId) =>
      gagal ? Stream.error(_galat) : super.watchShift(shiftId);

  @override
  Stream<List<RingkasanShift>> watchRiwayatShift(
    Periode periode, {
    String? hanyaUserId,
  }) => gagal
      ? Stream.error(_galat)
      : super.watchRiwayatShift(periode, hanyaUserId: hanyaUserId);
}

class _RiwayatGagal extends SalesRepository {
  _RiwayatGagal(super.db);
  var gagal = true;

  @override
  Stream<List<RingkasanHari>> watchHariRiwayat(SaringanRiwayat saringan) =>
      gagal ? Stream.error(_galat) : super.watchHariRiwayat(saringan);
}

class _IzinGagal extends PermissionRepository {
  _IzinGagal(super.db);
  var gagal = true;

  @override
  Future<List<Permission>> getAllPermissions() async {
    if (gagal) throw _galat;
    return super.getAllPermissions();
  }
}

class _PengeluaranGagal extends ExpenseRepository {
  _PengeluaranGagal(super.db);
  var gagal = true;

  @override
  Stream<List<Expense>> watchExpensesByShift(String shiftId) =>
      gagal ? Stream.error(_galat) : super.watchExpensesByShift(shiftId);

  @override
  Stream<List<Expense>> watchPengeluaranPeriode(Periode p) =>
      gagal ? Stream.error(_galat) : super.watchPengeluaranPeriode(p);
}

class _KasirGagal extends CashierRepository {
  _KasirGagal(super.db) : super(terhubung: () async => true);
  var gagal = true;

  @override
  Stream<List<RingkasanKasir>> watchDaftarKasir() =>
      gagal ? Stream.error(_galat) : super.watchDaftarKasir();
}

class _BillGagal extends OpenBillRepository {
  _BillGagal(super.db);
  var gagal = true;

  @override
  Stream<List<OpenBill>> watchTerbuka(String? shiftId) =>
      gagal ? Stream.error(_galat) : super.watchTerbuka(shiftId);
}

class _StrukGagal extends SalesRepository {
  _StrukGagal(super.db);
  var gagal = true;

  @override
  Future<List<TransactionItem>> getTransactionItems(
    String transactionId, {
    bool termasukBatal = false,
  }) async {
    if (gagal) throw _galat;
    return super.getTransactionItems(
      transactionId,
      termasukBatal: termasukBatal,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await SessionManager.instance.setSession(
      AuthSession.create(
        userId: 'o-1',
        username: 'owner',
        role: 'owner',
        shiftId: null,
        permissions: const ['manage_categories', 'view_all_shifts'],
      ),
    );
  });
  tearDown(() async {
    await SessionManager.instance.clearSession();
    await db.close();
  });

  Future<void> jalan(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> uji(
    WidgetTester t,
    Widget halaman, {
    required String pesan,
    required void Function() pulih,
    Future<void> Function()? siapkan,
  }) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: halaman)));
    await siapkan?.call();
    await jalan(t);
    expect(find.text('$pesan. Coba lagi.'), findsOneWidget);
    pulih();
    await t.tap(find.text('Coba lagi'));
    await jalan(t);
    expect(find.text('$pesan. Coba lagi.'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  /// Kasir yang sedang menjalankan shift.
  Future<void> masukShift() => SessionManager.instance.setSession(
    AuthSession.create(
      userId: 'k-1',
      username: 'sari',
      role: 'cashier',
      shiftId: 's-1',
      permissions: const ['create_transaction', 'manage_expenses'],
    ),
  );

  testWidgets('Pengeluaran kasir', (t) async {
    await t.runAsync(masukShift);
    final repo = _PengeluaranGagal(db);
    await uji(
      t,
      ExpensesPage(repo: repo, repoShift: ShiftRepository(db)),
      pesan: 'Pengeluaran gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Pengeluaran owner', (t) async {
    final repo = _PengeluaranGagal(db);
    await uji(
      t,
      PengeluaranOwnerPage(repo: repo),
      pesan: 'Pengeluaran gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Kelola Kasir', (t) async {
    final repo = _KasirGagal(db);
    await uji(
      t,
      KelolaKasirPage(repo: repo),
      pesan: 'Daftar kasir gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Dashboard kasir', (t) async {
    await t.runAsync(masukShift);
    final repo = _ShiftGagal(db);
    await uji(
      t,
      DasborKasirPage(keranjang: Keranjang(), repo: repo),
      pesan: 'Dashboard gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Tagihan open bill', (t) async {
    await t.runAsync(masukShift);
    final repo = _BillGagal(db);
    await uji(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => bukaDaftarOpenBill(
            context,
            Keranjang(),
            repo: repo,
            repoProduk: ProductRepository(db),
            repoJual: SalesRepository(db),
          ),
          child: const Text('buka'),
        ),
      ),
      siapkan: () => t.tap(find.text('buka')),
      pesan: 'Tagihan gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Detail struk', (t) async {
    final repo = _StrukGagal(db);
    final tx = Transaction(
      id: 't-1',
      invoiceNo: 'INV-1',
      total: 5000,
      paymentMethod: 'qris',
      createdAt: DateTime(2026, 11, 4),
      updatedAt: DateTime(2026, 11, 4),
      orderType: 'dine_in',
      syncStatus: 'synced',
    );
    await uji(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => TransactionDetailSheet(transaction: tx, repo: repo),
          ),
          child: const Text('buka'),
        ),
      ),
      siapkan: () => t.tap(find.text('buka')),
      pesan: 'Isi struk gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Kasir', (t) async {
    final repo = _ProdukGagal(db);
    await uji(
      t,
      SalesPage(keranjang: Keranjang(), repo: repo),
      pesan: 'Produk gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('audit nomor 54: kategori Kasir gagal dimuat → pesan dan '
      'Coba lagi', (t) async {
    final repo = _KategoriGagal(db);
    await uji(
      t,
      SalesPage(keranjang: Keranjang(), repo: repo),
      pesan: 'Kategori gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Kategori', (t) async {
    final repo = _ProdukGagal(db);
    await uji(
      t,
      KategoriPage(repo: repo),
      pesan: 'Kategori gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Riwayat Shift', (t) async {
    final repo = _ShiftGagal(db);
    await uji(
      t,
      RiwayatShiftPage(repo: repo),
      pesan: 'Riwayat shift gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Detail Shift', (t) async {
    final repo = _ShiftGagal(db);
    await uji(
      t,
      DetailShiftPage(shiftId: 's-1', repo: repo),
      pesan: 'Detail shift gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Riwayat transaksi', (t) async {
    final repo = _RiwayatGagal(db);
    await uji(
      t,
      DaftarRiwayat(
        saringan: const SaringanRiwayat(cakupan: CakupanRiwayat.semuaUntukTest),
        repo: repo,
        kepala: const [],
        kosong: (_) => const Text('kosong'),
      ),
      pesan: 'Riwayat gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('Hak Akses', (t) async {
    final repo = _IzinGagal(db);
    final akun = User(
      id: 'k-1',
      username: 'sari',
      pinHash: 'x',
      salt: 'x',
      role: 'cashier',
      isActive: true,
      loginAttempts: 0,
      recoveryAttempts: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      syncStatus: 'synced',
    );
    await uji(
      t,
      HakAksesPage(akun: akun, repo: repo),
      pesan: 'Hak akses gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('halaman Produk: kategori gagal dimuat → pesan dan Coba lagi, '
      'bukan deretan kategori yang hilang diam-diam', (t) async {
    final repo = _KategoriGagal(db);
    await uji(
      t,
      ProductsPage(repo: repo),
      pesan: 'Kategori gagal dimuat',
      pulih: () => repo.gagal = false,
    );
  });

  testWidgets('form produk: kategori gagal dimuat → tertulis di kolomnya, '
      'ketuk untuk mencoba lagi', (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = _KategoriGagal(db);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductFormSheet(simpan: (_) async {}, repo: repo),
        ),
      ),
    );
    await jalan(t);
    const tulisan = 'Gagal dimuat — ketuk untuk coba lagi';
    expect(find.text(tulisan), findsOneWidget);
    expect(find.text('Pilih Kategori'), findsNothing);
    repo.gagal = false;
    await t.tap(find.text(tulisan));
    await jalan(t);
    expect(find.text(tulisan), findsNothing);
    expect(find.text('Pilih Kategori'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('bagian pelengkap: galat aliran dicatat sekali, tidak ditelan',
      (t) async {
    final galat = Exception('aliran pelengkap gagal');
    final aliran = Stream<int>.error(galat);
    final sebelum = CatatanError.instance.isi.length;
    Widget layar() => MaterialApp(
          home: StreamBuilder<int>(
            stream: aliran.asBroadcastStream(),
            builder: (context, snap) {
              catatGalatAliran(snap, 'uji pelengkap');
              return const SizedBox.shrink();
            },
          ),
        );
    await t.pumpWidget(layar());
    await t.pump();
    // Dibangun ulang: galat yang sama tidak dicatat dua kali.
    await t.pump();
    await t.pump();
    final isi = CatatanError.instance.isi;
    expect(isi.length, sebelum + 1);
    expect(isi.last['sumber'], 'uji pelengkap');
    await t.pumpWidget(const SizedBox());
  });
}
