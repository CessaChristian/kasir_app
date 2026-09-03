import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_app/data/app_database.dart';
import 'package:kasir_app/data/models/sale_line.dart';
import 'package:kasir_app/features/auth/models/auth_session.dart';
import 'package:kasir_app/shared/auth/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengunci aturan: SEMUA primary key harus UUID.
///
/// Latar belakang — pernah ada 8 generator ID berbasis jam yang tersebar di
/// berbagai file (`prod_<ms>`, `shift_<µs>_<acak>`, dst). ID berbasis jam bisa
/// bentrok antar-device saat sync: dua HP yang membuat baris pada milidetik
/// yang sama menghasilkan ID identik, lalu salah satunya tertimpa.
///
/// Test ini punya dua lapis:
///   1. Perilaku  — method DB yang membuat ID sendiri harus menghasilkan UUID.
///   2. Sumber    — tidak boleh ada generator ID berbasis timestamp baru.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// UUID v4: 8-4-4-4-12 heksadesimal.
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('perilaku — ID yang dibuat DB layer', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());

      await db.into(db.users).insert(UsersCompanion.insert(
            id: const Value('owner-1'),
            username: 'owner',
            pinHash: 'hash',
            salt: 'salt',
            role: 'owner',
          ));
      await SessionManager.instance.setSession(AuthSession.create(
        userId: 'owner-1',
        username: 'owner',
        role: 'owner',
        shiftId: null,
        permissions: const [],
      ));
    });

    tearDown(() async {
      await SessionManager.instance.clearSession();
      await db.close();
    });

    test('addExpense menghasilkan id UUID', () async {
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: const Value('shift-1'),
            userId: 'owner-1',
          ));

      await db.addExpense(
        shiftId: 'shift-1',
        userId: 'owner-1',
        description: 'Beli gas',
        amount: 25000,
      );

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, matches(uuidV4),
          reason: 'id expense harus UUID v4, bukan ID berbasis jam');
    });

    test('createSale menghasilkan id UUID untuk setiap transaction item',
        () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value('prod-1'),
            name: 'Nasi Goreng',
            price: 15000,
          ));

      await db.createSale(
        transactionId: 'trx-1',
        paymentMethod: 'cash',
        cashReceived: 30000,
        orderType: 'dine_in',
        lines: [
          SaleLine(
            productId: 'prod-1',
            productName: 'Nasi Goreng',
            qty: 2,
            priceAtSale: 15000,
          ),
        ],
      );

      final items = await db.select(db.transactionItems).get();
      expect(items, hasLength(1));
      expect(items.single.id, matches(uuidV4),
          reason: 'id transaction_item harus UUID v4');
    });

    test('nomor nota disimpan terpisah dari primary key', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value('prod-1'),
            name: 'Es Teh',
            price: 5000,
          ));

      await db.createSale(
        transactionId: '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d',
        paymentMethod: 'qris',
        orderType: 'dine_in',
        lines: [
          SaleLine(
            productId: 'prod-1',
            productName: 'Es Teh',
            qty: 1,
            priceAtSale: 5000,
          ),
        ],
      );

      final tx = await db.select(db.transactions).getSingle();
      expect(tx.id, matches(uuidV4),
          reason: 'primary key harus UUID — dipakai untuk sync');
      expect(tx.invoiceNo, matches(RegExp(r'^TRX/\d{2}/\d{2}/\d{2}/\d{4,}$')),
          reason: 'nomor nota berformat TRX/dd/MM/yy/NNNN untuk struk');
      expect(tx.invoiceNo, isNot(tx.id),
          reason: 'keduanya peran berbeda, tidak boleh dicampur lagi');
    });
  });

  group('sumber — cegah generator ID berbasis timestamp muncul lagi', () {
    /// Pemakaian `SinceEpoch` yang SAH — bukan untuk primary key.
    /// Kalau menambah entri di sini, pastikan benar-benar bukan PK.
    const diizinkan = <String, String>{
      'lib/features/business/pages/business_detail_page.dart':
          'nama file logo, bukan primary key',
      'lib/data/app_database.dart':
          'konversi rentang tanggal ke epoch untuk query',
    };

    test('tidak ada pemakaian SinceEpoch di luar daftar yang diizinkan', () {
      final pelanggar = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;

        if (!entity.readAsStringSync().contains('SinceEpoch')) continue;

        final path = entity.path.replaceAll(r'\', '/');
        if (!diizinkan.containsKey(path)) pelanggar.add(path);
      }

      expect(
        pelanggar,
        isEmpty,
        reason: 'File di atas memakai timestamp untuk membuat ID. Primary key '
            'WAJIB pakai newUuid() dari lib/data/uuid_helper.dart supaya unik '
            'lintas device saat sync. Kalau pemakaiannya memang bukan primary '
            'key, tambahkan ke map `diizinkan` beserta alasannya.',
      );
    });
  });
}
