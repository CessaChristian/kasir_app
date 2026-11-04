import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/features/auth/repositories/permission_repository.dart';
import 'package:kasir_app/features/history/models/saringan_riwayat.dart';
import 'package:kasir_app/features/history/widgets/daftar_riwayat.dart';
import 'package:kasir_app/features/owner/pages/hak_akses_page.dart';
import 'package:kasir_app/features/products/pages/kategori_page.dart';
import 'package:kasir_app/features/products/repositories/product_repository.dart';
import 'package:kasir_app/features/sales/models/keranjang.dart';
import 'package:kasir_app/features/sales/repositories/sales_repository.dart';
import 'package:kasir_app/features/sales/sales_page.dart';
import 'package:kasir_app/features/shift/models/ringkasan_shift.dart';
import 'package:kasir_app/features/shift/pages/detail_shift_page.dart';
import 'package:kasir_app/features/shift/pages/riwayat_shift_page.dart';
import 'package:kasir_app/features/shift/repositories/shift_repository.dart';
import 'package:kasir_app/shared/auth/cakupan_riwayat.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:kasir_app/shared/ui/periode/periode.dart';
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
  }) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: halaman)));
    await jalan(t);
    expect(find.text('$pesan. Coba lagi.'), findsOneWidget);
    pulih();
    await t.tap(find.text('Coba lagi'));
    await jalan(t);
    expect(find.text('$pesan. Coba lagi.'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('Kasir', (t) async {
    final repo = _ProdukGagal(db);
    await uji(
      t,
      SalesPage(keranjang: Keranjang(), repo: repo),
      pesan: 'Produk gagal dimuat',
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
}
